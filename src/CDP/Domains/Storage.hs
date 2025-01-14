{-# LANGUAGE OverloadedStrings, RecordWildCards, TupleSections #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeFamilies #-}


{- |
  Storage 
-}


module CDP.Domains.Storage (module CDP.Domains.Storage) where

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


import CDP.Domains.BrowserTarget as BrowserTarget
import CDP.Domains.DOMPageNetworkEmulationSecurity as DOMPageNetworkEmulationSecurity


-- | Type 'Storage.SerializedStorageKey'.
type StorageSerializedStorageKey = String

-- | Type 'Storage.StorageType'.
--   Enum of possible storage types.
data StorageStorageType = StorageStorageTypeAppcache | StorageStorageTypeCookies | StorageStorageTypeFile_systems | StorageStorageTypeIndexeddb | StorageStorageTypeLocal_storage | StorageStorageTypeShader_cache | StorageStorageTypeWebsql | StorageStorageTypeService_workers | StorageStorageTypeCache_storage | StorageStorageTypeInterest_groups | StorageStorageTypeAll | StorageStorageTypeOther
   deriving (Ord, Eq, Show, Read)
instance FromJSON StorageStorageType where
   parseJSON = A.withText  "StorageStorageType"  $ \v -> do
      case v of
         "appcache" -> pure StorageStorageTypeAppcache
         "cookies" -> pure StorageStorageTypeCookies
         "file_systems" -> pure StorageStorageTypeFile_systems
         "indexeddb" -> pure StorageStorageTypeIndexeddb
         "local_storage" -> pure StorageStorageTypeLocal_storage
         "shader_cache" -> pure StorageStorageTypeShader_cache
         "websql" -> pure StorageStorageTypeWebsql
         "service_workers" -> pure StorageStorageTypeService_workers
         "cache_storage" -> pure StorageStorageTypeCache_storage
         "interest_groups" -> pure StorageStorageTypeInterest_groups
         "all" -> pure StorageStorageTypeAll
         "other" -> pure StorageStorageTypeOther
         _ -> fail "failed to parse StorageStorageType"

instance ToJSON StorageStorageType where
   toJSON v = A.String $
      case v of
         StorageStorageTypeAppcache -> "appcache"
         StorageStorageTypeCookies -> "cookies"
         StorageStorageTypeFile_systems -> "file_systems"
         StorageStorageTypeIndexeddb -> "indexeddb"
         StorageStorageTypeLocal_storage -> "local_storage"
         StorageStorageTypeShader_cache -> "shader_cache"
         StorageStorageTypeWebsql -> "websql"
         StorageStorageTypeService_workers -> "service_workers"
         StorageStorageTypeCache_storage -> "cache_storage"
         StorageStorageTypeInterest_groups -> "interest_groups"
         StorageStorageTypeAll -> "all"
         StorageStorageTypeOther -> "other"



-- | Type 'Storage.UsageForType'.
--   Usage for a storage type.
data StorageUsageForType = StorageUsageForType {
  -- | Name of storage type.
  storageUsageForTypeStorageType :: StorageStorageType,
  -- | Storage usage (bytes).
  storageUsageForTypeUsage :: Double
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageUsageForType  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 , A.omitNothingFields = True}

instance FromJSON  StorageUsageForType where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }



-- | Type 'Storage.TrustTokens'.
--   Pair of issuer origin and number of available (signed, but not used) Trust
--   Tokens from that issuer.
data StorageTrustTokens = StorageTrustTokens {
  storageTrustTokensIssuerOrigin :: String,
  storageTrustTokensCount :: Double
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageTrustTokens  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 18 , A.omitNothingFields = True}

instance FromJSON  StorageTrustTokens where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 18 }



-- | Type 'Storage.InterestGroupAccessType'.
--   Enum of interest group access types.
data StorageInterestGroupAccessType = StorageInterestGroupAccessTypeJoin | StorageInterestGroupAccessTypeLeave | StorageInterestGroupAccessTypeUpdate | StorageInterestGroupAccessTypeBid | StorageInterestGroupAccessTypeWin
   deriving (Ord, Eq, Show, Read)
instance FromJSON StorageInterestGroupAccessType where
   parseJSON = A.withText  "StorageInterestGroupAccessType"  $ \v -> do
      case v of
         "join" -> pure StorageInterestGroupAccessTypeJoin
         "leave" -> pure StorageInterestGroupAccessTypeLeave
         "update" -> pure StorageInterestGroupAccessTypeUpdate
         "bid" -> pure StorageInterestGroupAccessTypeBid
         "win" -> pure StorageInterestGroupAccessTypeWin
         _ -> fail "failed to parse StorageInterestGroupAccessType"

instance ToJSON StorageInterestGroupAccessType where
   toJSON v = A.String $
      case v of
         StorageInterestGroupAccessTypeJoin -> "join"
         StorageInterestGroupAccessTypeLeave -> "leave"
         StorageInterestGroupAccessTypeUpdate -> "update"
         StorageInterestGroupAccessTypeBid -> "bid"
         StorageInterestGroupAccessTypeWin -> "win"



-- | Type 'Storage.InterestGroupAd'.
--   Ad advertising element inside an interest group.
data StorageInterestGroupAd = StorageInterestGroupAd {
  storageInterestGroupAdRenderUrl :: String,
  storageInterestGroupAdMetadata :: Maybe String
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageInterestGroupAd  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 , A.omitNothingFields = True}

instance FromJSON  StorageInterestGroupAd where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 }



-- | Type 'Storage.InterestGroupDetails'.
--   The full details of an interest group.
data StorageInterestGroupDetails = StorageInterestGroupDetails {
  storageInterestGroupDetailsOwnerOrigin :: String,
  storageInterestGroupDetailsName :: String,
  storageInterestGroupDetailsExpirationTime :: DOMPageNetworkEmulationSecurity.NetworkTimeSinceEpoch,
  storageInterestGroupDetailsJoiningOrigin :: String,
  storageInterestGroupDetailsBiddingUrl :: Maybe String,
  storageInterestGroupDetailsBiddingWasmHelperUrl :: Maybe String,
  storageInterestGroupDetailsUpdateUrl :: Maybe String,
  storageInterestGroupDetailsTrustedBiddingSignalsUrl :: Maybe String,
  storageInterestGroupDetailsTrustedBiddingSignalsKeys :: [String],
  storageInterestGroupDetailsUserBiddingSignals :: Maybe String,
  storageInterestGroupDetailsAds :: [StorageInterestGroupAd],
  storageInterestGroupDetailsAdComponents :: [StorageInterestGroupAd]
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageInterestGroupDetails  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 27 , A.omitNothingFields = True}

instance FromJSON  StorageInterestGroupDetails where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 27 }





-- | Type of the 'Storage.cacheStorageContentUpdated' event.
data StorageCacheStorageContentUpdated = StorageCacheStorageContentUpdated {
  -- | Origin to update.
  storageCacheStorageContentUpdatedOrigin :: String,
  -- | Name of cache in origin.
  storageCacheStorageContentUpdatedCacheName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageCacheStorageContentUpdated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 , A.omitNothingFields = True}

instance FromJSON  StorageCacheStorageContentUpdated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 }


instance Event StorageCacheStorageContentUpdated where
    eventName _ = "Storage.cacheStorageContentUpdated"

-- | Type of the 'Storage.cacheStorageListUpdated' event.
data StorageCacheStorageListUpdated = StorageCacheStorageListUpdated {
  -- | Origin to update.
  storageCacheStorageListUpdatedOrigin :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageCacheStorageListUpdated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 , A.omitNothingFields = True}

instance FromJSON  StorageCacheStorageListUpdated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }


instance Event StorageCacheStorageListUpdated where
    eventName _ = "Storage.cacheStorageListUpdated"

-- | Type of the 'Storage.indexedDBContentUpdated' event.
data StorageIndexedDBContentUpdated = StorageIndexedDBContentUpdated {
  -- | Origin to update.
  storageIndexedDBContentUpdatedOrigin :: String,
  -- | Database to update.
  storageIndexedDBContentUpdatedDatabaseName :: String,
  -- | ObjectStore to update.
  storageIndexedDBContentUpdatedObjectStoreName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageIndexedDBContentUpdated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 , A.omitNothingFields = True}

instance FromJSON  StorageIndexedDBContentUpdated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }


instance Event StorageIndexedDBContentUpdated where
    eventName _ = "Storage.indexedDBContentUpdated"

-- | Type of the 'Storage.indexedDBListUpdated' event.
data StorageIndexedDBListUpdated = StorageIndexedDBListUpdated {
  -- | Origin to update.
  storageIndexedDBListUpdatedOrigin :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageIndexedDBListUpdated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 27 , A.omitNothingFields = True}

instance FromJSON  StorageIndexedDBListUpdated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 27 }


instance Event StorageIndexedDBListUpdated where
    eventName _ = "Storage.indexedDBListUpdated"

-- | Type of the 'Storage.interestGroupAccessed' event.
data StorageInterestGroupAccessed = StorageInterestGroupAccessed {
  storageInterestGroupAccessedAccessTime :: DOMPageNetworkEmulationSecurity.NetworkTimeSinceEpoch,
  storageInterestGroupAccessedType :: StorageInterestGroupAccessType,
  storageInterestGroupAccessedOwnerOrigin :: String,
  storageInterestGroupAccessedName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON StorageInterestGroupAccessed  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 28 , A.omitNothingFields = True}

instance FromJSON  StorageInterestGroupAccessed where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 28 }


instance Event StorageInterestGroupAccessed where
    eventName _ = "Storage.interestGroupAccessed"



-- | Parameters of the 'storageGetStorageKeyForFrame' command.
data PStorageGetStorageKeyForFrame = PStorageGetStorageKeyForFrame {
  pStorageGetStorageKeyForFrameFrameId :: DOMPageNetworkEmulationSecurity.PageFrameId
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageGetStorageKeyForFrame  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 29 , A.omitNothingFields = True}

instance FromJSON  PStorageGetStorageKeyForFrame where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 29 }


-- | Function for the 'Storage.getStorageKeyForFrame' command.
--   Returns a storage key given a frame id.
--   Returns: 'PStorageGetStorageKeyForFrame'
--   Returns: 'StorageGetStorageKeyForFrame'
storageGetStorageKeyForFrame :: Handle -> PStorageGetStorageKeyForFrame -> IO StorageGetStorageKeyForFrame
storageGetStorageKeyForFrame handle params = sendReceiveCommandResult handle params

-- | Return type of the 'storageGetStorageKeyForFrame' command.
data StorageGetStorageKeyForFrame = StorageGetStorageKeyForFrame {
  storageGetStorageKeyForFrameStorageKey :: StorageSerializedStorageKey
} deriving (Generic, Eq, Show, Read)

instance FromJSON  StorageGetStorageKeyForFrame where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 28 }

instance Command PStorageGetStorageKeyForFrame where
    type CommandResponse PStorageGetStorageKeyForFrame = StorageGetStorageKeyForFrame
    commandName _ = "Storage.getStorageKeyForFrame"


-- | Parameters of the 'storageClearDataForOrigin' command.
data PStorageClearDataForOrigin = PStorageClearDataForOrigin {
  -- | Security origin.
  pStorageClearDataForOriginOrigin :: String,
  -- | Comma separated list of StorageType to clear.
  pStorageClearDataForOriginStorageTypes :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageClearDataForOrigin  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 26 , A.omitNothingFields = True}

instance FromJSON  PStorageClearDataForOrigin where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 26 }


-- | Function for the 'Storage.clearDataForOrigin' command.
--   Clears storage for origin.
--   Returns: 'PStorageClearDataForOrigin'
storageClearDataForOrigin :: Handle -> PStorageClearDataForOrigin -> IO ()
storageClearDataForOrigin handle params = sendReceiveCommand handle params

instance Command PStorageClearDataForOrigin where
    type CommandResponse PStorageClearDataForOrigin = NoResponse
    commandName _ = "Storage.clearDataForOrigin"


-- | Parameters of the 'storageGetCookies' command.
data PStorageGetCookies = PStorageGetCookies {
  -- | Browser context to use when called on the browser endpoint.
  pStorageGetCookiesBrowserContextId :: Maybe BrowserTarget.BrowserBrowserContextID
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageGetCookies  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 18 , A.omitNothingFields = True}

instance FromJSON  PStorageGetCookies where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 18 }


-- | Function for the 'Storage.getCookies' command.
--   Returns all browser cookies.
--   Returns: 'PStorageGetCookies'
--   Returns: 'StorageGetCookies'
storageGetCookies :: Handle -> PStorageGetCookies -> IO StorageGetCookies
storageGetCookies handle params = sendReceiveCommandResult handle params

-- | Return type of the 'storageGetCookies' command.
data StorageGetCookies = StorageGetCookies {
  -- | Array of cookie objects.
  storageGetCookiesCookies :: [DOMPageNetworkEmulationSecurity.NetworkCookie]
} deriving (Generic, Eq, Show, Read)

instance FromJSON  StorageGetCookies where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 }

instance Command PStorageGetCookies where
    type CommandResponse PStorageGetCookies = StorageGetCookies
    commandName _ = "Storage.getCookies"


-- | Parameters of the 'storageSetCookies' command.
data PStorageSetCookies = PStorageSetCookies {
  -- | Cookies to be set.
  pStorageSetCookiesCookies :: [DOMPageNetworkEmulationSecurity.NetworkCookieParam],
  -- | Browser context to use when called on the browser endpoint.
  pStorageSetCookiesBrowserContextId :: Maybe BrowserTarget.BrowserBrowserContextID
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageSetCookies  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 18 , A.omitNothingFields = True}

instance FromJSON  PStorageSetCookies where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 18 }


-- | Function for the 'Storage.setCookies' command.
--   Sets given cookies.
--   Returns: 'PStorageSetCookies'
storageSetCookies :: Handle -> PStorageSetCookies -> IO ()
storageSetCookies handle params = sendReceiveCommand handle params

instance Command PStorageSetCookies where
    type CommandResponse PStorageSetCookies = NoResponse
    commandName _ = "Storage.setCookies"


-- | Parameters of the 'storageClearCookies' command.
data PStorageClearCookies = PStorageClearCookies {
  -- | Browser context to use when called on the browser endpoint.
  pStorageClearCookiesBrowserContextId :: Maybe BrowserTarget.BrowserBrowserContextID
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageClearCookies  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 , A.omitNothingFields = True}

instance FromJSON  PStorageClearCookies where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 }


-- | Function for the 'Storage.clearCookies' command.
--   Clears cookies.
--   Returns: 'PStorageClearCookies'
storageClearCookies :: Handle -> PStorageClearCookies -> IO ()
storageClearCookies handle params = sendReceiveCommand handle params

instance Command PStorageClearCookies where
    type CommandResponse PStorageClearCookies = NoResponse
    commandName _ = "Storage.clearCookies"


-- | Parameters of the 'storageGetUsageAndQuota' command.
data PStorageGetUsageAndQuota = PStorageGetUsageAndQuota {
  -- | Security origin.
  pStorageGetUsageAndQuotaOrigin :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageGetUsageAndQuota  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 24 , A.omitNothingFields = True}

instance FromJSON  PStorageGetUsageAndQuota where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 24 }


-- | Function for the 'Storage.getUsageAndQuota' command.
--   Returns usage and quota in bytes.
--   Returns: 'PStorageGetUsageAndQuota'
--   Returns: 'StorageGetUsageAndQuota'
storageGetUsageAndQuota :: Handle -> PStorageGetUsageAndQuota -> IO StorageGetUsageAndQuota
storageGetUsageAndQuota handle params = sendReceiveCommandResult handle params

-- | Return type of the 'storageGetUsageAndQuota' command.
data StorageGetUsageAndQuota = StorageGetUsageAndQuota {
  -- | Storage usage (bytes).
  storageGetUsageAndQuotaUsage :: Double,
  -- | Storage quota (bytes).
  storageGetUsageAndQuotaQuota :: Double,
  -- | Whether or not the origin has an active storage quota override
  storageGetUsageAndQuotaOverrideActive :: Bool,
  -- | Storage usage per type (bytes).
  storageGetUsageAndQuotaUsageBreakdown :: [StorageUsageForType]
} deriving (Generic, Eq, Show, Read)

instance FromJSON  StorageGetUsageAndQuota where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 }

instance Command PStorageGetUsageAndQuota where
    type CommandResponse PStorageGetUsageAndQuota = StorageGetUsageAndQuota
    commandName _ = "Storage.getUsageAndQuota"


-- | Parameters of the 'storageOverrideQuotaForOrigin' command.
data PStorageOverrideQuotaForOrigin = PStorageOverrideQuotaForOrigin {
  -- | Security origin.
  pStorageOverrideQuotaForOriginOrigin :: String,
  -- | The quota size (in bytes) to override the original quota with.
  --   If this is called multiple times, the overridden quota will be equal to
  --   the quotaSize provided in the final call. If this is called without
  --   specifying a quotaSize, the quota will be reset to the default value for
  --   the specified origin. If this is called multiple times with different
  --   origins, the override will be maintained for each origin until it is
  --   disabled (called without a quotaSize).
  pStorageOverrideQuotaForOriginQuotaSize :: Maybe Double
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageOverrideQuotaForOrigin  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 , A.omitNothingFields = True}

instance FromJSON  PStorageOverrideQuotaForOrigin where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }


-- | Function for the 'Storage.overrideQuotaForOrigin' command.
--   Override quota for the specified origin
--   Returns: 'PStorageOverrideQuotaForOrigin'
storageOverrideQuotaForOrigin :: Handle -> PStorageOverrideQuotaForOrigin -> IO ()
storageOverrideQuotaForOrigin handle params = sendReceiveCommand handle params

instance Command PStorageOverrideQuotaForOrigin where
    type CommandResponse PStorageOverrideQuotaForOrigin = NoResponse
    commandName _ = "Storage.overrideQuotaForOrigin"


-- | Parameters of the 'storageTrackCacheStorageForOrigin' command.
data PStorageTrackCacheStorageForOrigin = PStorageTrackCacheStorageForOrigin {
  -- | Security origin.
  pStorageTrackCacheStorageForOriginOrigin :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageTrackCacheStorageForOrigin  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 34 , A.omitNothingFields = True}

instance FromJSON  PStorageTrackCacheStorageForOrigin where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 34 }


-- | Function for the 'Storage.trackCacheStorageForOrigin' command.
--   Registers origin to be notified when an update occurs to its cache storage list.
--   Returns: 'PStorageTrackCacheStorageForOrigin'
storageTrackCacheStorageForOrigin :: Handle -> PStorageTrackCacheStorageForOrigin -> IO ()
storageTrackCacheStorageForOrigin handle params = sendReceiveCommand handle params

instance Command PStorageTrackCacheStorageForOrigin where
    type CommandResponse PStorageTrackCacheStorageForOrigin = NoResponse
    commandName _ = "Storage.trackCacheStorageForOrigin"


-- | Parameters of the 'storageTrackIndexedDBForOrigin' command.
data PStorageTrackIndexedDBForOrigin = PStorageTrackIndexedDBForOrigin {
  -- | Security origin.
  pStorageTrackIndexedDBForOriginOrigin :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageTrackIndexedDBForOrigin  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 , A.omitNothingFields = True}

instance FromJSON  PStorageTrackIndexedDBForOrigin where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 }


-- | Function for the 'Storage.trackIndexedDBForOrigin' command.
--   Registers origin to be notified when an update occurs to its IndexedDB.
--   Returns: 'PStorageTrackIndexedDBForOrigin'
storageTrackIndexedDBForOrigin :: Handle -> PStorageTrackIndexedDBForOrigin -> IO ()
storageTrackIndexedDBForOrigin handle params = sendReceiveCommand handle params

instance Command PStorageTrackIndexedDBForOrigin where
    type CommandResponse PStorageTrackIndexedDBForOrigin = NoResponse
    commandName _ = "Storage.trackIndexedDBForOrigin"


-- | Parameters of the 'storageUntrackCacheStorageForOrigin' command.
data PStorageUntrackCacheStorageForOrigin = PStorageUntrackCacheStorageForOrigin {
  -- | Security origin.
  pStorageUntrackCacheStorageForOriginOrigin :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageUntrackCacheStorageForOrigin  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 36 , A.omitNothingFields = True}

instance FromJSON  PStorageUntrackCacheStorageForOrigin where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 36 }


-- | Function for the 'Storage.untrackCacheStorageForOrigin' command.
--   Unregisters origin from receiving notifications for cache storage.
--   Returns: 'PStorageUntrackCacheStorageForOrigin'
storageUntrackCacheStorageForOrigin :: Handle -> PStorageUntrackCacheStorageForOrigin -> IO ()
storageUntrackCacheStorageForOrigin handle params = sendReceiveCommand handle params

instance Command PStorageUntrackCacheStorageForOrigin where
    type CommandResponse PStorageUntrackCacheStorageForOrigin = NoResponse
    commandName _ = "Storage.untrackCacheStorageForOrigin"


-- | Parameters of the 'storageUntrackIndexedDBForOrigin' command.
data PStorageUntrackIndexedDBForOrigin = PStorageUntrackIndexedDBForOrigin {
  -- | Security origin.
  pStorageUntrackIndexedDBForOriginOrigin :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageUntrackIndexedDBForOrigin  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 , A.omitNothingFields = True}

instance FromJSON  PStorageUntrackIndexedDBForOrigin where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 }


-- | Function for the 'Storage.untrackIndexedDBForOrigin' command.
--   Unregisters origin from receiving notifications for IndexedDB.
--   Returns: 'PStorageUntrackIndexedDBForOrigin'
storageUntrackIndexedDBForOrigin :: Handle -> PStorageUntrackIndexedDBForOrigin -> IO ()
storageUntrackIndexedDBForOrigin handle params = sendReceiveCommand handle params

instance Command PStorageUntrackIndexedDBForOrigin where
    type CommandResponse PStorageUntrackIndexedDBForOrigin = NoResponse
    commandName _ = "Storage.untrackIndexedDBForOrigin"


-- | Parameters of the 'storageGetTrustTokens' command.
data PStorageGetTrustTokens = PStorageGetTrustTokens
instance ToJSON PStorageGetTrustTokens where toJSON _ = A.Null

-- | Function for the 'Storage.getTrustTokens' command.
--   Returns the number of stored Trust Tokens per issuer for the
--   current browsing context.
--   Returns: 'StorageGetTrustTokens'
storageGetTrustTokens :: Handle -> IO StorageGetTrustTokens
storageGetTrustTokens handle = sendReceiveCommandResult handle PStorageGetTrustTokens

-- | Return type of the 'storageGetTrustTokens' command.
data StorageGetTrustTokens = StorageGetTrustTokens {
  storageGetTrustTokensTokens :: [StorageTrustTokens]
} deriving (Generic, Eq, Show, Read)

instance FromJSON  StorageGetTrustTokens where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 }

instance Command PStorageGetTrustTokens where
    type CommandResponse PStorageGetTrustTokens = StorageGetTrustTokens
    commandName _ = "Storage.getTrustTokens"


-- | Parameters of the 'storageClearTrustTokens' command.
data PStorageClearTrustTokens = PStorageClearTrustTokens {
  pStorageClearTrustTokensIssuerOrigin :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageClearTrustTokens  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 24 , A.omitNothingFields = True}

instance FromJSON  PStorageClearTrustTokens where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 24 }


-- | Function for the 'Storage.clearTrustTokens' command.
--   Removes all Trust Tokens issued by the provided issuerOrigin.
--   Leaves other stored data, including the issuer's Redemption Records, intact.
--   Returns: 'PStorageClearTrustTokens'
--   Returns: 'StorageClearTrustTokens'
storageClearTrustTokens :: Handle -> PStorageClearTrustTokens -> IO StorageClearTrustTokens
storageClearTrustTokens handle params = sendReceiveCommandResult handle params

-- | Return type of the 'storageClearTrustTokens' command.
data StorageClearTrustTokens = StorageClearTrustTokens {
  -- | True if any tokens were deleted, false otherwise.
  storageClearTrustTokensDidDeleteTokens :: Bool
} deriving (Generic, Eq, Show, Read)

instance FromJSON  StorageClearTrustTokens where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 }

instance Command PStorageClearTrustTokens where
    type CommandResponse PStorageClearTrustTokens = StorageClearTrustTokens
    commandName _ = "Storage.clearTrustTokens"


-- | Parameters of the 'storageGetInterestGroupDetails' command.
data PStorageGetInterestGroupDetails = PStorageGetInterestGroupDetails {
  pStorageGetInterestGroupDetailsOwnerOrigin :: String,
  pStorageGetInterestGroupDetailsName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageGetInterestGroupDetails  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 , A.omitNothingFields = True}

instance FromJSON  PStorageGetInterestGroupDetails where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 }


-- | Function for the 'Storage.getInterestGroupDetails' command.
--   Gets details for a named interest group.
--   Returns: 'PStorageGetInterestGroupDetails'
--   Returns: 'StorageGetInterestGroupDetails'
storageGetInterestGroupDetails :: Handle -> PStorageGetInterestGroupDetails -> IO StorageGetInterestGroupDetails
storageGetInterestGroupDetails handle params = sendReceiveCommandResult handle params

-- | Return type of the 'storageGetInterestGroupDetails' command.
data StorageGetInterestGroupDetails = StorageGetInterestGroupDetails {
  storageGetInterestGroupDetailsDetails :: StorageInterestGroupDetails
} deriving (Generic, Eq, Show, Read)

instance FromJSON  StorageGetInterestGroupDetails where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }

instance Command PStorageGetInterestGroupDetails where
    type CommandResponse PStorageGetInterestGroupDetails = StorageGetInterestGroupDetails
    commandName _ = "Storage.getInterestGroupDetails"


-- | Parameters of the 'storageSetInterestGroupTracking' command.
data PStorageSetInterestGroupTracking = PStorageSetInterestGroupTracking {
  pStorageSetInterestGroupTrackingEnable :: Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PStorageSetInterestGroupTracking  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 , A.omitNothingFields = True}

instance FromJSON  PStorageSetInterestGroupTracking where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 }


-- | Function for the 'Storage.setInterestGroupTracking' command.
--   Enables/Disables issuing of interestGroupAccessed events.
--   Returns: 'PStorageSetInterestGroupTracking'
storageSetInterestGroupTracking :: Handle -> PStorageSetInterestGroupTracking -> IO ()
storageSetInterestGroupTracking handle params = sendReceiveCommand handle params

instance Command PStorageSetInterestGroupTracking where
    type CommandResponse PStorageSetInterestGroupTracking = NoResponse
    commandName _ = "Storage.setInterestGroupTracking"



