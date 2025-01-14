{-# LANGUAGE OverloadedStrings, RecordWildCards, TupleSections #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeFamilies #-}


{- |
  Cast :
     A domain for interacting with Cast, Presentation API, and Remote Playback API
     functionalities.

-}


module CDP.Domains.Cast (module CDP.Domains.Cast) where

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




-- | Type 'Cast.Sink'.
data CastSink = CastSink {
  castSinkName :: String,
  castSinkId :: String,
  -- | Text describing the current session. Present only if there is an active
  --   session on the sink.
  castSinkSession :: Maybe String
} deriving (Generic, Eq, Show, Read)
instance ToJSON CastSink  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 8 , A.omitNothingFields = True}

instance FromJSON  CastSink where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 8 }





-- | Type of the 'Cast.sinksUpdated' event.
data CastSinksUpdated = CastSinksUpdated {
  castSinksUpdatedSinks :: [CastSink]
} deriving (Generic, Eq, Show, Read)
instance ToJSON CastSinksUpdated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 , A.omitNothingFields = True}

instance FromJSON  CastSinksUpdated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 }


instance Event CastSinksUpdated where
    eventName _ = "Cast.sinksUpdated"

-- | Type of the 'Cast.issueUpdated' event.
data CastIssueUpdated = CastIssueUpdated {
  castIssueUpdatedIssueMessage :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON CastIssueUpdated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 , A.omitNothingFields = True}

instance FromJSON  CastIssueUpdated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 }


instance Event CastIssueUpdated where
    eventName _ = "Cast.issueUpdated"



-- | Parameters of the 'castEnable' command.
data PCastEnable = PCastEnable {
  pCastEnablePresentationUrl :: Maybe String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PCastEnable  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 11 , A.omitNothingFields = True}

instance FromJSON  PCastEnable where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 11 }


-- | Function for the 'Cast.enable' command.
--   Starts observing for sinks that can be used for tab mirroring, and if set,
--   sinks compatible with |presentationUrl| as well. When sinks are found, a
--   |sinksUpdated| event is fired.
--   Also starts observing for issue messages. When an issue is added or removed,
--   an |issueUpdated| event is fired.
--   Returns: 'PCastEnable'
castEnable :: Handle -> PCastEnable -> IO ()
castEnable handle params = sendReceiveCommand handle params

instance Command PCastEnable where
    type CommandResponse PCastEnable = NoResponse
    commandName _ = "Cast.enable"


-- | Parameters of the 'castDisable' command.
data PCastDisable = PCastDisable
instance ToJSON PCastDisable where toJSON _ = A.Null

-- | Function for the 'Cast.disable' command.
--   Stops observing for sinks and issues.
castDisable :: Handle -> IO ()
castDisable handle = sendReceiveCommand handle PCastDisable

instance Command PCastDisable where
    type CommandResponse PCastDisable = NoResponse
    commandName _ = "Cast.disable"


-- | Parameters of the 'castSetSinkToUse' command.
data PCastSetSinkToUse = PCastSetSinkToUse {
  pCastSetSinkToUseSinkName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PCastSetSinkToUse  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 , A.omitNothingFields = True}

instance FromJSON  PCastSetSinkToUse where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 }


-- | Function for the 'Cast.setSinkToUse' command.
--   Sets a sink to be used when the web page requests the browser to choose a
--   sink via Presentation API, Remote Playback API, or Cast SDK.
--   Returns: 'PCastSetSinkToUse'
castSetSinkToUse :: Handle -> PCastSetSinkToUse -> IO ()
castSetSinkToUse handle params = sendReceiveCommand handle params

instance Command PCastSetSinkToUse where
    type CommandResponse PCastSetSinkToUse = NoResponse
    commandName _ = "Cast.setSinkToUse"


-- | Parameters of the 'castStartDesktopMirroring' command.
data PCastStartDesktopMirroring = PCastStartDesktopMirroring {
  pCastStartDesktopMirroringSinkName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PCastStartDesktopMirroring  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 26 , A.omitNothingFields = True}

instance FromJSON  PCastStartDesktopMirroring where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 26 }


-- | Function for the 'Cast.startDesktopMirroring' command.
--   Starts mirroring the desktop to the sink.
--   Returns: 'PCastStartDesktopMirroring'
castStartDesktopMirroring :: Handle -> PCastStartDesktopMirroring -> IO ()
castStartDesktopMirroring handle params = sendReceiveCommand handle params

instance Command PCastStartDesktopMirroring where
    type CommandResponse PCastStartDesktopMirroring = NoResponse
    commandName _ = "Cast.startDesktopMirroring"


-- | Parameters of the 'castStartTabMirroring' command.
data PCastStartTabMirroring = PCastStartTabMirroring {
  pCastStartTabMirroringSinkName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PCastStartTabMirroring  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 , A.omitNothingFields = True}

instance FromJSON  PCastStartTabMirroring where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 }


-- | Function for the 'Cast.startTabMirroring' command.
--   Starts mirroring the tab to the sink.
--   Returns: 'PCastStartTabMirroring'
castStartTabMirroring :: Handle -> PCastStartTabMirroring -> IO ()
castStartTabMirroring handle params = sendReceiveCommand handle params

instance Command PCastStartTabMirroring where
    type CommandResponse PCastStartTabMirroring = NoResponse
    commandName _ = "Cast.startTabMirroring"


-- | Parameters of the 'castStopCasting' command.
data PCastStopCasting = PCastStopCasting {
  pCastStopCastingSinkName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PCastStopCasting  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 , A.omitNothingFields = True}

instance FromJSON  PCastStopCasting where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 }


-- | Function for the 'Cast.stopCasting' command.
--   Stops the active Cast session on the sink.
--   Returns: 'PCastStopCasting'
castStopCasting :: Handle -> PCastStopCasting -> IO ()
castStopCasting handle params = sendReceiveCommand handle params

instance Command PCastStopCasting where
    type CommandResponse PCastStopCasting = NoResponse
    commandName _ = "Cast.stopCasting"



