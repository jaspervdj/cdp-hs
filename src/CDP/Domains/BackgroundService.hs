{-# LANGUAGE OverloadedStrings, RecordWildCards, TupleSections #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeFamilies #-}


{- |
  BackgroundService :
     Defines events for background web platform features.

-}


module CDP.Domains.BackgroundService (module CDP.Domains.BackgroundService) where

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


import CDP.Domains.DOMPageNetworkEmulationSecurity as DOMPageNetworkEmulationSecurity
import CDP.Domains.ServiceWorker as ServiceWorker


-- | Type 'BackgroundService.ServiceName'.
--   The Background Service that will be associated with the commands/events.
--   Every Background Service operates independently, but they share the same
--   API.
data BackgroundServiceServiceName = BackgroundServiceServiceNameBackgroundFetch | BackgroundServiceServiceNameBackgroundSync | BackgroundServiceServiceNamePushMessaging | BackgroundServiceServiceNameNotifications | BackgroundServiceServiceNamePaymentHandler | BackgroundServiceServiceNamePeriodicBackgroundSync
   deriving (Ord, Eq, Show, Read)
instance FromJSON BackgroundServiceServiceName where
   parseJSON = A.withText  "BackgroundServiceServiceName"  $ \v -> do
      case v of
         "backgroundFetch" -> pure BackgroundServiceServiceNameBackgroundFetch
         "backgroundSync" -> pure BackgroundServiceServiceNameBackgroundSync
         "pushMessaging" -> pure BackgroundServiceServiceNamePushMessaging
         "notifications" -> pure BackgroundServiceServiceNameNotifications
         "paymentHandler" -> pure BackgroundServiceServiceNamePaymentHandler
         "periodicBackgroundSync" -> pure BackgroundServiceServiceNamePeriodicBackgroundSync
         _ -> fail "failed to parse BackgroundServiceServiceName"

instance ToJSON BackgroundServiceServiceName where
   toJSON v = A.String $
      case v of
         BackgroundServiceServiceNameBackgroundFetch -> "backgroundFetch"
         BackgroundServiceServiceNameBackgroundSync -> "backgroundSync"
         BackgroundServiceServiceNamePushMessaging -> "pushMessaging"
         BackgroundServiceServiceNameNotifications -> "notifications"
         BackgroundServiceServiceNamePaymentHandler -> "paymentHandler"
         BackgroundServiceServiceNamePeriodicBackgroundSync -> "periodicBackgroundSync"



-- | Type 'BackgroundService.EventMetadata'.
--   A key-value pair for additional event information to pass along.
data BackgroundServiceEventMetadata = BackgroundServiceEventMetadata {
  backgroundServiceEventMetadataKey :: String,
  backgroundServiceEventMetadataValue :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON BackgroundServiceEventMetadata  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 , A.omitNothingFields = True}

instance FromJSON  BackgroundServiceEventMetadata where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }



-- | Type 'BackgroundService.BackgroundServiceEvent'.
data BackgroundServiceBackgroundServiceEvent = BackgroundServiceBackgroundServiceEvent {
  -- | Timestamp of the event (in seconds).
  backgroundServiceBackgroundServiceEventTimestamp :: DOMPageNetworkEmulationSecurity.NetworkTimeSinceEpoch,
  -- | The origin this event belongs to.
  backgroundServiceBackgroundServiceEventOrigin :: String,
  -- | The Service Worker ID that initiated the event.
  backgroundServiceBackgroundServiceEventServiceWorkerRegistrationId :: ServiceWorker.ServiceWorkerRegistrationID,
  -- | The Background Service this event belongs to.
  backgroundServiceBackgroundServiceEventService :: BackgroundServiceServiceName,
  -- | A description of the event.
  backgroundServiceBackgroundServiceEventEventName :: String,
  -- | An identifier that groups related events together.
  backgroundServiceBackgroundServiceEventInstanceId :: String,
  -- | A list of event-specific information.
  backgroundServiceBackgroundServiceEventEventMetadata :: [BackgroundServiceEventMetadata]
} deriving (Generic, Eq, Show, Read)
instance ToJSON BackgroundServiceBackgroundServiceEvent  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 39 , A.omitNothingFields = True}

instance FromJSON  BackgroundServiceBackgroundServiceEvent where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 39 }





-- | Type of the 'BackgroundService.recordingStateChanged' event.
data BackgroundServiceRecordingStateChanged = BackgroundServiceRecordingStateChanged {
  backgroundServiceRecordingStateChangedIsRecording :: Bool,
  backgroundServiceRecordingStateChangedService :: BackgroundServiceServiceName
} deriving (Generic, Eq, Show, Read)
instance ToJSON BackgroundServiceRecordingStateChanged  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 , A.omitNothingFields = True}

instance FromJSON  BackgroundServiceRecordingStateChanged where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 }


instance Event BackgroundServiceRecordingStateChanged where
    eventName _ = "BackgroundService.recordingStateChanged"

-- | Type of the 'BackgroundService.backgroundServiceEventReceived' event.
data BackgroundServiceBackgroundServiceEventReceived = BackgroundServiceBackgroundServiceEventReceived {
  backgroundServiceBackgroundServiceEventReceivedBackgroundServiceEvent :: BackgroundServiceBackgroundServiceEvent
} deriving (Generic, Eq, Show, Read)
instance ToJSON BackgroundServiceBackgroundServiceEventReceived  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 47 , A.omitNothingFields = True}

instance FromJSON  BackgroundServiceBackgroundServiceEventReceived where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 47 }


instance Event BackgroundServiceBackgroundServiceEventReceived where
    eventName _ = "BackgroundService.backgroundServiceEventReceived"



-- | Parameters of the 'backgroundServiceStartObserving' command.
data PBackgroundServiceStartObserving = PBackgroundServiceStartObserving {
  pBackgroundServiceStartObservingService :: BackgroundServiceServiceName
} deriving (Generic, Eq, Show, Read)
instance ToJSON PBackgroundServiceStartObserving  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 , A.omitNothingFields = True}

instance FromJSON  PBackgroundServiceStartObserving where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 }


-- | Function for the 'BackgroundService.startObserving' command.
--   Enables event updates for the service.
--   Returns: 'PBackgroundServiceStartObserving'
backgroundServiceStartObserving :: Handle -> PBackgroundServiceStartObserving -> IO ()
backgroundServiceStartObserving handle params = sendReceiveCommand handle params

instance Command PBackgroundServiceStartObserving where
    type CommandResponse PBackgroundServiceStartObserving = NoResponse
    commandName _ = "BackgroundService.startObserving"


-- | Parameters of the 'backgroundServiceStopObserving' command.
data PBackgroundServiceStopObserving = PBackgroundServiceStopObserving {
  pBackgroundServiceStopObservingService :: BackgroundServiceServiceName
} deriving (Generic, Eq, Show, Read)
instance ToJSON PBackgroundServiceStopObserving  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 , A.omitNothingFields = True}

instance FromJSON  PBackgroundServiceStopObserving where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 }


-- | Function for the 'BackgroundService.stopObserving' command.
--   Disables event updates for the service.
--   Returns: 'PBackgroundServiceStopObserving'
backgroundServiceStopObserving :: Handle -> PBackgroundServiceStopObserving -> IO ()
backgroundServiceStopObserving handle params = sendReceiveCommand handle params

instance Command PBackgroundServiceStopObserving where
    type CommandResponse PBackgroundServiceStopObserving = NoResponse
    commandName _ = "BackgroundService.stopObserving"


-- | Parameters of the 'backgroundServiceSetRecording' command.
data PBackgroundServiceSetRecording = PBackgroundServiceSetRecording {
  pBackgroundServiceSetRecordingShouldRecord :: Bool,
  pBackgroundServiceSetRecordingService :: BackgroundServiceServiceName
} deriving (Generic, Eq, Show, Read)
instance ToJSON PBackgroundServiceSetRecording  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 , A.omitNothingFields = True}

instance FromJSON  PBackgroundServiceSetRecording where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }


-- | Function for the 'BackgroundService.setRecording' command.
--   Set the recording state for the service.
--   Returns: 'PBackgroundServiceSetRecording'
backgroundServiceSetRecording :: Handle -> PBackgroundServiceSetRecording -> IO ()
backgroundServiceSetRecording handle params = sendReceiveCommand handle params

instance Command PBackgroundServiceSetRecording where
    type CommandResponse PBackgroundServiceSetRecording = NoResponse
    commandName _ = "BackgroundService.setRecording"


-- | Parameters of the 'backgroundServiceClearEvents' command.
data PBackgroundServiceClearEvents = PBackgroundServiceClearEvents {
  pBackgroundServiceClearEventsService :: BackgroundServiceServiceName
} deriving (Generic, Eq, Show, Read)
instance ToJSON PBackgroundServiceClearEvents  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 29 , A.omitNothingFields = True}

instance FromJSON  PBackgroundServiceClearEvents where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 29 }


-- | Function for the 'BackgroundService.clearEvents' command.
--   Clears all stored data for the service.
--   Returns: 'PBackgroundServiceClearEvents'
backgroundServiceClearEvents :: Handle -> PBackgroundServiceClearEvents -> IO ()
backgroundServiceClearEvents handle params = sendReceiveCommand handle params

instance Command PBackgroundServiceClearEvents where
    type CommandResponse PBackgroundServiceClearEvents = NoResponse
    commandName _ = "BackgroundService.clearEvents"



