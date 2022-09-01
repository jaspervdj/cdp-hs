{-# LANGUAGE OverloadedStrings, RecordWildCards, TupleSections, GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE AllowAmbiguousTypes    #-}
{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs                  #-}
{-# LANGUAGE PolyKinds              #-}
{-# LANGUAGE RankNTypes             #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE TypeApplications       #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE TypeOperators          #-}
{-# LANGUAGE UndecidableInstances   #-}

module Utils (module Utils) where

import           Control.Applicative  ((<$>))
import           Control.Monad
import           Control.Monad.Loops
import           Control.Monad.Trans  (liftIO)
import qualified Data.Map             as M
import           Data.Maybe          
import Data.Functor.Identity
import Data.String
import qualified Data.Text as T
import qualified Data.List as List
import qualified Data.Text.IO         as TI
import qualified Data.Vector          as V
import Data.Aeson.Types (Parser(..))
import           Data.Aeson           (FromJSON (..), ToJSON (..), (.:), (.:?), (.=), (.!=), (.:!))
import qualified Data.Aeson           as A
import qualified Network.HTTP.Simple as Http
import qualified Network.URI          as Uri
import qualified Network.WebSockets as WS
import Control.Concurrent
import qualified Text.Casing as C
import qualified Data.ByteString.Lazy as BS
import qualified Data.Map as Map
import Data.Proxy
import System.Random


data ToJSONEx where
    ToJSONEx :: (ToJSON a, Show a) => a -> ToJSONEx
instance ToJSON ToJSONEx where
    toJSON (ToJSONEx v) = toJSON v
instance Show ToJSONEx where
    show (ToJSONEx v) = show v

newtype CommandId = CommandId { unCommandId :: Int }
    deriving (Eq, Ord, Show, ToJSON)

instance FromJSON CommandId where
    parseJSON = A.withObject "CommandId" $ \obj -> do
        CommandId <$> obj .: "id"

data CommandObj a = CommandObj {
    coId :: CommandId
    , coMethod :: String
    , coParams :: Maybe a
    } deriving Show

instance (ToJSON a) => ToJSON (CommandObj a) where
    toJSON cmd = A.object . concat $
            [ [ "id"     .= coId cmd ]
            , [ "method" .= coMethod cmd ]
            , maybe [] (\p -> [ "params" .= p ]) $ coParams cmd
            ]

randomCommandId :: MVar StdGen -> IO CommandId
randomCommandId mg = modifyMVar mg $ \g -> do
    let (id, g2) = uniformR (0 :: Int, 1000 :: Int) g
    pure (g2, CommandId id)

class (FromJSON b) => Command b where
    commandName               :: Proxy b -> String

data CommandResponse b where
    CommandResponse :: Command b => CommandId -> Maybe b -> CommandResponse b
instance (Show b) => Show (CommandResponse b) where
    show (CommandResponse id result) = "\nid: " <> show id <> "\nresult: " <> show result

newtype Error = Error String
    deriving Show

newtype InternalError = InternalError String
    deriving Show

indent :: Int -> String -> String
indent = (<>) . flip replicate ' '

sendCommand :: forall a. (ToJSON a) => WS.Connection -> CommandId -> String -> Maybe a -> IO ()
sendCommand conn id name params = do
    let co = CommandObj id name params
    WS.sendTextData conn . A.encode $ co
  where
    paramsProxy = Proxy :: Proxy a
        
receiveResponse :: forall b. Command b => MVar CommandBuffer -> CommandId -> IO (Either InternalError (CommandResponse b))
receiveResponse buffer id = do
    bs <- untilJust $ do
            bsM <- Map.lookup id <$> readMVar buffer
            if isNothing bsM
                then threadDelay 1000 -- :CONFIG
                else pure ()

            pure bsM

    pure $ maybe (Left . InternalError $ "error in parsing response") Right . A.decode $ bs
  where
    p = Proxy :: Proxy b

sendReceiveCommandResult' :: forall a b ev. (ToJSON a, Command b) => Session' ev -> String -> Maybe a -> IO (Either Error b)
sendReceiveCommandResult' session name params = do
    id <- randomCommandId $ randomGen session
    sendCommand (conn session) id name params
    response <- receiveResponse (commandBuffer session) id
    pure $ case response of
        Left _ -> Left . Error $ "internal error"
        Right (CommandResponse _ resultM) -> maybe (Left . Error $ "error in parsing result") Right $ resultM    
  where
    resultProxy = Proxy :: Proxy b
    
sendReceiveCommand' :: (ToJSON a) => Session' ev -> String -> Maybe a -> IO (Maybe Error)
sendReceiveCommand' session name params = do
    id <- randomCommandId $ randomGen session
    sendCommand (conn session) id name params
    response <- receiveResponse (commandBuffer session) id :: IO (Either InternalError (CommandResponse NoResponse))
    pure $ case response of
        Left _                            -> Just . Error $ "internal error"
        Right (CommandResponse _ resultM) -> maybe Nothing (const . Just . Error $ "got an unexpected result") $ resultM  

instance (Command b) => FromJSON (CommandResponse b) where
    parseJSON = A.withObject "CommandResponse" $ \obj -> do
        crId <- CommandId <$> obj .: "id"
        CommandResponse (crId :: CommandId) <$> obj .:? "result"

data NoResponse = NoResponse
instance Command NoResponse where
    commandName _ = "noresponse"
instance FromJSON NoResponse where
    parseJSON _ = fail "noresponse"    


type CommandBuffer = Map.Map CommandId BS.ByteString

data Session' ev = MkSession 
    { randomGen      :: MVar StdGen
    , events         :: MVar (Map.Map String (ev -> IO ()))
    , commandBuffer  :: MVar CommandBuffer
    , conn           :: WS.Connection
    , listenThread   :: ThreadId
    }

type FromJSONEvent ev = FromJSON (EventResponse ev)

updateEvents :: forall ev. FromJSONEvent ev => Session' ev -> (Map.Map String (ev -> IO ()) -> Map.Map String (ev -> IO ())) -> IO ()
updateEvents session f = ($ pure . f) . modifyMVar_ . events $ session

subscribe' :: forall ev a . (FromJSONEvent ev, FromEvent ev a) => Session' ev -> (a -> IO ()) -> IO ()
subscribe' session h = updateEvents session $ Map.insert (eventName ps p) handler
  where
    handler = maybe (pure ()) h . fromEvent
    p  = (Proxy :: Proxy a)
    ps = (Proxy :: Proxy s)

unsubscribe' :: forall ev a. (FromJSONEvent ev, FromEvent ev a) => Session' ev -> Proxy a -> IO ()
unsubscribe' session p = updateEvents session (Map.delete (eventName ps p))
  where
    ps = Proxy :: Proxy ev


class (FromJSON a) => FromEvent ev a | a -> ev where
    eventName     :: Proxy ev -> Proxy a -> String
    fromEvent     :: ev       -> Maybe a

data EventResponse ev where
    EventResponse :: (Show ev, Show a, FromEvent ev a) => Proxy ev -> Proxy a -> Maybe ev -> EventResponse ev

    