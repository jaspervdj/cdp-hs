{-# LANGUAGE OverloadedStrings, GADTs, RecordWildCards, TupleSections  #-}
module Utils where
import           Control.Applicative  ((<$>))
import           Control.Monad
import           Control.Monad.Trans  (liftIO)
import qualified Data.Map             as M
import           Data.Maybe           (catMaybes, fromMaybe)
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
data CommandResponseResult a = CommandResponseResult { crrId :: Int, crrResult :: a }
data CommandResponse = CommandResponse { crId :: Int }

instance (Show a) => Show (CommandResponseResult a) where
    show CommandResponseResult{..} = "\nid: " <> show crrId <> "\nresult: " <> show crrResult
instance Show CommandResponse where
    show CommandResponse{..} = "\nid: " <> show crId

instance (FromJSON a) => FromJSON (CommandResponseResult a) where
    parseJSON = A.withObject "CommandResponseResult" $ \obj -> do
        crrId <- obj .: "id"
        crrResult <- obj .: "result"
        pure CommandResponseResult{..}

instance FromJSON CommandResponse where
    parseJSON = A.withObject "CommandResponse" $ \obj -> do
        crId <- obj .: "id"
        pure CommandResponse{..}


data ToJSONEx where
   ToJSONEx :: (ToJSON a, Show a) => a -> ToJSONEx
instance ToJSON ToJSONEx where
    toJSON (ToJSONEx v) = toJSON v
instance Show ToJSONEx where
    show (ToJSONEx v) = show v
data Command = Command {
      commandId :: Int
    , commandMethod :: String
    , commandParams :: [(String, ToJSONEx)]
    } deriving Show
instance ToJSON Command where
   toJSON cmd = A.object
        [ "id"     .= commandId cmd
        , "method" .= commandMethod cmd
        , "params" .= commandParams cmd
        ]

data Session a = MkSession 
    { events       :: a
    , conn         :: WS.Connection
    , listenThread :: ThreadId
    }


newtype Error = Error String
    deriving Show

indent :: Int -> String -> String
indent = (<>) . flip replicate ' '

commandToStr :: Command -> String
commandToStr Command{..} = unlines 
    [ "command: " <> commandMethod
    , if (not . null) commandParams 
        then "arguments: " <> (unlines . map (indent 2 . (\(f,s) -> f <> ":" <> s) . fmap show) $ commandParams)
        else ""
    ]

sendCommand :: WS.Connection -> (String, String) -> [(String, ToJSONEx)] -> IO Command
sendCommand conn (domain,method) paramArgs = do
    putStrLn . show $ (domain, method)
    id <- pure 1  -- TODO: randomly generate
    let c = command id
    WS.sendTextData conn . A.encode $ c
    pure c
  where
    command id = Command id 
        (domain <> "." <> method)
        paramArgs
   
receiveResponse :: (FromJSON a) => WS.Connection -> IO (Maybe a)
receiveResponse conn = A.decode <$> do
    dm <- WS.receiveDataMessage conn
    putStrLn . show $ dm
    pure $ WS.fromDataMessage dm

sendReceiveCommandResult :: FromJSON b =>
    WS.Connection ->
         (String, String) -> [(String, ToJSONEx)]
         -> IO (Either Error b)
sendReceiveCommandResult conn (domain,method) paramArgs = do
    command <- sendCommand conn (domain,method) paramArgs
    res     <- receiveResponse conn
    pure $ maybe (Left . responseParseError $ command) 
        (maybe (Left . responseParseError $ command) Right . crrResult) res 

sendReceiveCommand ::
    WS.Connection ->
         (String, String) -> [(String, ToJSONEx)]
         -> IO (Maybe Error)
sendReceiveCommand conn (domain,method) paramArgs = do
    command <- sendCommand conn (domain, method) paramArgs
    res     <- receiveResponse conn
    pure $ maybe (Just . responseParseError $ command) 
        (const Nothing . crId) res

responseParseError :: Command -> Error
responseParseError c = Error . unlines $
    ["unable to parse response", commandToStr c]

