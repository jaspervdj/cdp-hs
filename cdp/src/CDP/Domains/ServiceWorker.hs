{-# LANGUAGE OverloadedStrings, RecordWildCards, TupleSections #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}

module CDP.Domains.ServiceWorker (module CDP.Domains.ServiceWorker) where

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
import GHC.Generics
import Data.Char
import Data.Default

import CDP.Internal.Runtime
import CDP.Handle

import CDP.Domains.BrowserTarget as BrowserTarget


type ServiceWorkerRegistrationId = String

data ServiceWorkerServiceWorkerRegistration = ServiceWorkerServiceWorkerRegistration {
   serviceWorkerServiceWorkerRegistrationRegistrationId :: ServiceWorkerRegistrationId,
   serviceWorkerServiceWorkerRegistrationScopeUrl :: String,
   serviceWorkerServiceWorkerRegistrationIsDeleted :: Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON ServiceWorkerServiceWorkerRegistration  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 , A.omitNothingFields = True}

instance FromJSON  ServiceWorkerServiceWorkerRegistration where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 }


data ServiceWorkerServiceWorkerVersionRunningStatus = ServiceWorkerServiceWorkerVersionRunningStatusStopped | ServiceWorkerServiceWorkerVersionRunningStatusStarting | ServiceWorkerServiceWorkerVersionRunningStatusRunning | ServiceWorkerServiceWorkerVersionRunningStatusStopping
   deriving (Ord, Eq, Show, Read)
instance FromJSON ServiceWorkerServiceWorkerVersionRunningStatus where
   parseJSON = A.withText  "ServiceWorkerServiceWorkerVersionRunningStatus"  $ \v -> do
      case v of
         "stopped" -> pure ServiceWorkerServiceWorkerVersionRunningStatusStopped
         "starting" -> pure ServiceWorkerServiceWorkerVersionRunningStatusStarting
         "running" -> pure ServiceWorkerServiceWorkerVersionRunningStatusRunning
         "stopping" -> pure ServiceWorkerServiceWorkerVersionRunningStatusStopping
         _ -> fail "failed to parse ServiceWorkerServiceWorkerVersionRunningStatus"

instance ToJSON ServiceWorkerServiceWorkerVersionRunningStatus where
   toJSON v = A.String $
      case v of
         ServiceWorkerServiceWorkerVersionRunningStatusStopped -> "stopped"
         ServiceWorkerServiceWorkerVersionRunningStatusStarting -> "starting"
         ServiceWorkerServiceWorkerVersionRunningStatusRunning -> "running"
         ServiceWorkerServiceWorkerVersionRunningStatusStopping -> "stopping"


data ServiceWorkerServiceWorkerVersionStatus = ServiceWorkerServiceWorkerVersionStatusNew | ServiceWorkerServiceWorkerVersionStatusInstalling | ServiceWorkerServiceWorkerVersionStatusInstalled | ServiceWorkerServiceWorkerVersionStatusActivating | ServiceWorkerServiceWorkerVersionStatusActivated | ServiceWorkerServiceWorkerVersionStatusRedundant
   deriving (Ord, Eq, Show, Read)
instance FromJSON ServiceWorkerServiceWorkerVersionStatus where
   parseJSON = A.withText  "ServiceWorkerServiceWorkerVersionStatus"  $ \v -> do
      case v of
         "new" -> pure ServiceWorkerServiceWorkerVersionStatusNew
         "installing" -> pure ServiceWorkerServiceWorkerVersionStatusInstalling
         "installed" -> pure ServiceWorkerServiceWorkerVersionStatusInstalled
         "activating" -> pure ServiceWorkerServiceWorkerVersionStatusActivating
         "activated" -> pure ServiceWorkerServiceWorkerVersionStatusActivated
         "redundant" -> pure ServiceWorkerServiceWorkerVersionStatusRedundant
         _ -> fail "failed to parse ServiceWorkerServiceWorkerVersionStatus"

instance ToJSON ServiceWorkerServiceWorkerVersionStatus where
   toJSON v = A.String $
      case v of
         ServiceWorkerServiceWorkerVersionStatusNew -> "new"
         ServiceWorkerServiceWorkerVersionStatusInstalling -> "installing"
         ServiceWorkerServiceWorkerVersionStatusInstalled -> "installed"
         ServiceWorkerServiceWorkerVersionStatusActivating -> "activating"
         ServiceWorkerServiceWorkerVersionStatusActivated -> "activated"
         ServiceWorkerServiceWorkerVersionStatusRedundant -> "redundant"



data ServiceWorkerServiceWorkerVersion = ServiceWorkerServiceWorkerVersion {
   serviceWorkerServiceWorkerVersionVersionId :: String,
   serviceWorkerServiceWorkerVersionRegistrationId :: ServiceWorkerRegistrationId,
   serviceWorkerServiceWorkerVersionScriptUrl :: String,
   serviceWorkerServiceWorkerVersionRunningStatus :: ServiceWorkerServiceWorkerVersionRunningStatus,
   serviceWorkerServiceWorkerVersionStatus :: ServiceWorkerServiceWorkerVersionStatus,
   serviceWorkerServiceWorkerVersionScriptLastModified :: Maybe Double,
   serviceWorkerServiceWorkerVersionScriptResponseTime :: Maybe Double,
   serviceWorkerServiceWorkerVersionControlledClients :: Maybe [BrowserTarget.TargetTargetId],
   serviceWorkerServiceWorkerVersionTargetId :: Maybe BrowserTarget.TargetTargetId
} deriving (Generic, Eq, Show, Read)
instance ToJSON ServiceWorkerServiceWorkerVersion  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 , A.omitNothingFields = True}

instance FromJSON  ServiceWorkerServiceWorkerVersion where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 }



data ServiceWorkerServiceWorkerErrorMessage = ServiceWorkerServiceWorkerErrorMessage {
   serviceWorkerServiceWorkerErrorMessageErrorMessage :: String,
   serviceWorkerServiceWorkerErrorMessageRegistrationId :: ServiceWorkerRegistrationId,
   serviceWorkerServiceWorkerErrorMessageVersionId :: String,
   serviceWorkerServiceWorkerErrorMessageSourceUrl :: String,
   serviceWorkerServiceWorkerErrorMessageLineNumber :: Int,
   serviceWorkerServiceWorkerErrorMessageColumnNumber :: Int
} deriving (Generic, Eq, Show, Read)
instance ToJSON ServiceWorkerServiceWorkerErrorMessage  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 , A.omitNothingFields = True}

instance FromJSON  ServiceWorkerServiceWorkerErrorMessage where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 }





data ServiceWorkerWorkerErrorReported = ServiceWorkerWorkerErrorReported {
   serviceWorkerWorkerErrorReportedErrorMessage :: ServiceWorkerServiceWorkerErrorMessage
} deriving (Generic, Eq, Show, Read)
instance ToJSON ServiceWorkerWorkerErrorReported  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 , A.omitNothingFields = True}

instance FromJSON  ServiceWorkerWorkerErrorReported where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 }



data ServiceWorkerWorkerRegistrationUpdated = ServiceWorkerWorkerRegistrationUpdated {
   serviceWorkerWorkerRegistrationUpdatedRegistrations :: [ServiceWorkerServiceWorkerRegistration]
} deriving (Generic, Eq, Show, Read)
instance ToJSON ServiceWorkerWorkerRegistrationUpdated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 , A.omitNothingFields = True}

instance FromJSON  ServiceWorkerWorkerRegistrationUpdated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 }



data ServiceWorkerWorkerVersionUpdated = ServiceWorkerWorkerVersionUpdated {
   serviceWorkerWorkerVersionUpdatedVersions :: [ServiceWorkerServiceWorkerVersion]
} deriving (Generic, Eq, Show, Read)
instance ToJSON ServiceWorkerWorkerVersionUpdated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 , A.omitNothingFields = True}

instance FromJSON  ServiceWorkerWorkerVersionUpdated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 }





data PServiceWorkerDeliverPushMessage = PServiceWorkerDeliverPushMessage {
   pServiceWorkerDeliverPushMessageOrigin :: String,
   pServiceWorkerDeliverPushMessageRegistrationId :: ServiceWorkerRegistrationId,
   pServiceWorkerDeliverPushMessageData :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerDeliverPushMessage  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerDeliverPushMessage where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 }


serviceWorkerDeliverPushMessage :: Handle ev -> PServiceWorkerDeliverPushMessage -> IO (Maybe Error)
serviceWorkerDeliverPushMessage handle params = sendReceiveCommand handle "ServiceWorker.deliverPushMessage" (Just params)


serviceWorkerDisable :: Handle ev -> IO (Maybe Error)
serviceWorkerDisable handle = sendReceiveCommand handle "ServiceWorker.disable" (Nothing :: Maybe ())



data PServiceWorkerDispatchSyncEvent = PServiceWorkerDispatchSyncEvent {
   pServiceWorkerDispatchSyncEventOrigin :: String,
   pServiceWorkerDispatchSyncEventRegistrationId :: ServiceWorkerRegistrationId,
   pServiceWorkerDispatchSyncEventTag :: String,
   pServiceWorkerDispatchSyncEventLastChance :: Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerDispatchSyncEvent  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerDispatchSyncEvent where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 }


serviceWorkerDispatchSyncEvent :: Handle ev -> PServiceWorkerDispatchSyncEvent -> IO (Maybe Error)
serviceWorkerDispatchSyncEvent handle params = sendReceiveCommand handle "ServiceWorker.dispatchSyncEvent" (Just params)



data PServiceWorkerDispatchPeriodicSyncEvent = PServiceWorkerDispatchPeriodicSyncEvent {
   pServiceWorkerDispatchPeriodicSyncEventOrigin :: String,
   pServiceWorkerDispatchPeriodicSyncEventRegistrationId :: ServiceWorkerRegistrationId,
   pServiceWorkerDispatchPeriodicSyncEventTag :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerDispatchPeriodicSyncEvent  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 39 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerDispatchPeriodicSyncEvent where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 39 }


serviceWorkerDispatchPeriodicSyncEvent :: Handle ev -> PServiceWorkerDispatchPeriodicSyncEvent -> IO (Maybe Error)
serviceWorkerDispatchPeriodicSyncEvent handle params = sendReceiveCommand handle "ServiceWorker.dispatchPeriodicSyncEvent" (Just params)


serviceWorkerEnable :: Handle ev -> IO (Maybe Error)
serviceWorkerEnable handle = sendReceiveCommand handle "ServiceWorker.enable" (Nothing :: Maybe ())



data PServiceWorkerInspectWorker = PServiceWorkerInspectWorker {
   pServiceWorkerInspectWorkerVersionId :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerInspectWorker  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 27 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerInspectWorker where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 27 }


serviceWorkerInspectWorker :: Handle ev -> PServiceWorkerInspectWorker -> IO (Maybe Error)
serviceWorkerInspectWorker handle params = sendReceiveCommand handle "ServiceWorker.inspectWorker" (Just params)



data PServiceWorkerSetForceUpdateOnPageLoad = PServiceWorkerSetForceUpdateOnPageLoad {
   pServiceWorkerSetForceUpdateOnPageLoadForceUpdateOnPageLoad :: Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerSetForceUpdateOnPageLoad  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerSetForceUpdateOnPageLoad where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 38 }


serviceWorkerSetForceUpdateOnPageLoad :: Handle ev -> PServiceWorkerSetForceUpdateOnPageLoad -> IO (Maybe Error)
serviceWorkerSetForceUpdateOnPageLoad handle params = sendReceiveCommand handle "ServiceWorker.setForceUpdateOnPageLoad" (Just params)



data PServiceWorkerSkipWaiting = PServiceWorkerSkipWaiting {
   pServiceWorkerSkipWaitingScopeUrl :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerSkipWaiting  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 25 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerSkipWaiting where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 25 }


serviceWorkerSkipWaiting :: Handle ev -> PServiceWorkerSkipWaiting -> IO (Maybe Error)
serviceWorkerSkipWaiting handle params = sendReceiveCommand handle "ServiceWorker.skipWaiting" (Just params)



data PServiceWorkerStartWorker = PServiceWorkerStartWorker {
   pServiceWorkerStartWorkerScopeUrl :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerStartWorker  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 25 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerStartWorker where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 25 }


serviceWorkerStartWorker :: Handle ev -> PServiceWorkerStartWorker -> IO (Maybe Error)
serviceWorkerStartWorker handle params = sendReceiveCommand handle "ServiceWorker.startWorker" (Just params)


serviceWorkerStopAllWorkers :: Handle ev -> IO (Maybe Error)
serviceWorkerStopAllWorkers handle = sendReceiveCommand handle "ServiceWorker.stopAllWorkers" (Nothing :: Maybe ())



data PServiceWorkerStopWorker = PServiceWorkerStopWorker {
   pServiceWorkerStopWorkerVersionId :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerStopWorker  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 24 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerStopWorker where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 24 }


serviceWorkerStopWorker :: Handle ev -> PServiceWorkerStopWorker -> IO (Maybe Error)
serviceWorkerStopWorker handle params = sendReceiveCommand handle "ServiceWorker.stopWorker" (Just params)



data PServiceWorkerUnregister = PServiceWorkerUnregister {
   pServiceWorkerUnregisterScopeUrl :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerUnregister  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 24 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerUnregister where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 24 }


serviceWorkerUnregister :: Handle ev -> PServiceWorkerUnregister -> IO (Maybe Error)
serviceWorkerUnregister handle params = sendReceiveCommand handle "ServiceWorker.unregister" (Just params)



data PServiceWorkerUpdateRegistration = PServiceWorkerUpdateRegistration {
   pServiceWorkerUpdateRegistrationScopeUrl :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PServiceWorkerUpdateRegistration  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 , A.omitNothingFields = True}

instance FromJSON  PServiceWorkerUpdateRegistration where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 }


serviceWorkerUpdateRegistration :: Handle ev -> PServiceWorkerUpdateRegistration -> IO (Maybe Error)
serviceWorkerUpdateRegistration handle params = sendReceiveCommand handle "ServiceWorker.updateRegistration" (Just params)


