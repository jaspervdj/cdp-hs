{-# LANGUAGE OverloadedStrings, RecordWildCards, TupleSections #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeFamilies #-}


{- |
  Inspector 
-}


module CDP.Domains.Inspector (module CDP.Domains.Inspector) where

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
import qualified Data.ByteString.Lazy as BS
import qualified Data.Map as Map
import Data.Proxy
import System.Random
import GHC.Generics
import Data.Char
import Data.Default

import CDP.Internal.Runtime






-- | Type of the 'Inspector.detached' event.
data InspectorDetached = InspectorDetached {
  -- | The reason why connection has been terminated.
  inspectorDetachedReason :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON InspectorDetached  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 , A.omitNothingFields = True}

instance FromJSON  InspectorDetached where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 }


instance Event InspectorDetached where
    eventName _ = "Inspector.detached"

-- | Type of the 'Inspector.targetCrashed' event.
data InspectorTargetCrashed = InspectorTargetCrashed
   deriving (Eq, Show, Read)
instance FromJSON InspectorTargetCrashed where
   parseJSON = A.withText  "InspectorTargetCrashed"  $ \v -> do
      case v of
         "InspectorTargetCrashed" -> pure InspectorTargetCrashed
         _ -> fail "failed to parse InspectorTargetCrashed"


instance Event InspectorTargetCrashed where
    eventName _ = "Inspector.targetCrashed"

-- | Type of the 'Inspector.targetReloadedAfterCrash' event.
data InspectorTargetReloadedAfterCrash = InspectorTargetReloadedAfterCrash
   deriving (Eq, Show, Read)
instance FromJSON InspectorTargetReloadedAfterCrash where
   parseJSON = A.withText  "InspectorTargetReloadedAfterCrash"  $ \v -> do
      case v of
         "InspectorTargetReloadedAfterCrash" -> pure InspectorTargetReloadedAfterCrash
         _ -> fail "failed to parse InspectorTargetReloadedAfterCrash"


instance Event InspectorTargetReloadedAfterCrash where
    eventName _ = "Inspector.targetReloadedAfterCrash"



-- | Parameters of the 'inspectorDisable' command.
data PInspectorDisable = PInspectorDisable
instance ToJSON PInspectorDisable where toJSON _ = A.Null

-- | Function for the 'Inspector.disable' command.
--   Disables inspector domain notifications.
inspectorDisable :: Handle -> IO ()
inspectorDisable handle = sendReceiveCommand handle PInspectorDisable

instance Command PInspectorDisable where
    type CommandResponse PInspectorDisable = NoResponse
    commandName _ = "Inspector.disable"


-- | Parameters of the 'inspectorEnable' command.
data PInspectorEnable = PInspectorEnable
instance ToJSON PInspectorEnable where toJSON _ = A.Null

-- | Function for the 'Inspector.enable' command.
--   Enables inspector domain notifications.
inspectorEnable :: Handle -> IO ()
inspectorEnable handle = sendReceiveCommand handle PInspectorEnable

instance Command PInspectorEnable where
    type CommandResponse PInspectorEnable = NoResponse
    commandName _ = "Inspector.enable"



