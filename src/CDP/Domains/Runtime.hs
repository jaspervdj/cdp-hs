{-# LANGUAGE OverloadedStrings, RecordWildCards, TupleSections #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeFamilies #-}


{- |
  Runtime :
     Runtime domain exposes JavaScript runtime by means of remote evaluation and mirror objects.
     Evaluation results are returned as mirror object that expose object type, string representation
     and unique identifier that can be used for further object reference. Original objects are
     maintained in memory unless they are either explicitly released or are released along with the
     other objects in their object group.

-}


module CDP.Domains.Runtime (module CDP.Domains.Runtime) where

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




-- | Type 'Runtime.ScriptId'.
--   Unique script identifier.
type RuntimeScriptId = String

-- | Type 'Runtime.WebDriverValue'.
--   Represents the value serialiazed by the WebDriver BiDi specification
--   https://w3c.github.io/webdriver-bidi.
data RuntimeWebDriverValueType = RuntimeWebDriverValueTypeUndefined | RuntimeWebDriverValueTypeNull | RuntimeWebDriverValueTypeString | RuntimeWebDriverValueTypeNumber | RuntimeWebDriverValueTypeBoolean | RuntimeWebDriverValueTypeBigint | RuntimeWebDriverValueTypeRegexp | RuntimeWebDriverValueTypeDate | RuntimeWebDriverValueTypeSymbol | RuntimeWebDriverValueTypeArray | RuntimeWebDriverValueTypeObject | RuntimeWebDriverValueTypeFunction | RuntimeWebDriverValueTypeMap | RuntimeWebDriverValueTypeSet | RuntimeWebDriverValueTypeWeakmap | RuntimeWebDriverValueTypeWeakset | RuntimeWebDriverValueTypeError | RuntimeWebDriverValueTypeProxy | RuntimeWebDriverValueTypePromise | RuntimeWebDriverValueTypeTypedarray | RuntimeWebDriverValueTypeArraybuffer | RuntimeWebDriverValueTypeNode | RuntimeWebDriverValueTypeWindow
   deriving (Ord, Eq, Show, Read)
instance FromJSON RuntimeWebDriverValueType where
   parseJSON = A.withText  "RuntimeWebDriverValueType"  $ \v -> do
      case v of
         "undefined" -> pure RuntimeWebDriverValueTypeUndefined
         "null" -> pure RuntimeWebDriverValueTypeNull
         "string" -> pure RuntimeWebDriverValueTypeString
         "number" -> pure RuntimeWebDriverValueTypeNumber
         "boolean" -> pure RuntimeWebDriverValueTypeBoolean
         "bigint" -> pure RuntimeWebDriverValueTypeBigint
         "regexp" -> pure RuntimeWebDriverValueTypeRegexp
         "date" -> pure RuntimeWebDriverValueTypeDate
         "symbol" -> pure RuntimeWebDriverValueTypeSymbol
         "array" -> pure RuntimeWebDriverValueTypeArray
         "object" -> pure RuntimeWebDriverValueTypeObject
         "function" -> pure RuntimeWebDriverValueTypeFunction
         "map" -> pure RuntimeWebDriverValueTypeMap
         "set" -> pure RuntimeWebDriverValueTypeSet
         "weakmap" -> pure RuntimeWebDriverValueTypeWeakmap
         "weakset" -> pure RuntimeWebDriverValueTypeWeakset
         "error" -> pure RuntimeWebDriverValueTypeError
         "proxy" -> pure RuntimeWebDriverValueTypeProxy
         "promise" -> pure RuntimeWebDriverValueTypePromise
         "typedarray" -> pure RuntimeWebDriverValueTypeTypedarray
         "arraybuffer" -> pure RuntimeWebDriverValueTypeArraybuffer
         "node" -> pure RuntimeWebDriverValueTypeNode
         "window" -> pure RuntimeWebDriverValueTypeWindow
         _ -> fail "failed to parse RuntimeWebDriverValueType"

instance ToJSON RuntimeWebDriverValueType where
   toJSON v = A.String $
      case v of
         RuntimeWebDriverValueTypeUndefined -> "undefined"
         RuntimeWebDriverValueTypeNull -> "null"
         RuntimeWebDriverValueTypeString -> "string"
         RuntimeWebDriverValueTypeNumber -> "number"
         RuntimeWebDriverValueTypeBoolean -> "boolean"
         RuntimeWebDriverValueTypeBigint -> "bigint"
         RuntimeWebDriverValueTypeRegexp -> "regexp"
         RuntimeWebDriverValueTypeDate -> "date"
         RuntimeWebDriverValueTypeSymbol -> "symbol"
         RuntimeWebDriverValueTypeArray -> "array"
         RuntimeWebDriverValueTypeObject -> "object"
         RuntimeWebDriverValueTypeFunction -> "function"
         RuntimeWebDriverValueTypeMap -> "map"
         RuntimeWebDriverValueTypeSet -> "set"
         RuntimeWebDriverValueTypeWeakmap -> "weakmap"
         RuntimeWebDriverValueTypeWeakset -> "weakset"
         RuntimeWebDriverValueTypeError -> "error"
         RuntimeWebDriverValueTypeProxy -> "proxy"
         RuntimeWebDriverValueTypePromise -> "promise"
         RuntimeWebDriverValueTypeTypedarray -> "typedarray"
         RuntimeWebDriverValueTypeArraybuffer -> "arraybuffer"
         RuntimeWebDriverValueTypeNode -> "node"
         RuntimeWebDriverValueTypeWindow -> "window"



data RuntimeWebDriverValue = RuntimeWebDriverValue {
  runtimeWebDriverValueType :: RuntimeWebDriverValueType,
  runtimeWebDriverValueValue :: Maybe Int,
  runtimeWebDriverValueObjectId :: Maybe String
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeWebDriverValue  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 , A.omitNothingFields = True}

instance FromJSON  RuntimeWebDriverValue where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 }



-- | Type 'Runtime.RemoteObjectId'.
--   Unique object identifier.
type RuntimeRemoteObjectId = String

-- | Type 'Runtime.UnserializableValue'.
--   Primitive value which cannot be JSON-stringified. Includes values `-0`, `NaN`, `Infinity`,
--   `-Infinity`, and bigint literals.
type RuntimeUnserializableValue = String

-- | Type 'Runtime.RemoteObject'.
--   Mirror object referencing original JavaScript object.
data RuntimeRemoteObjectType = RuntimeRemoteObjectTypeObject | RuntimeRemoteObjectTypeFunction | RuntimeRemoteObjectTypeUndefined | RuntimeRemoteObjectTypeString | RuntimeRemoteObjectTypeNumber | RuntimeRemoteObjectTypeBoolean | RuntimeRemoteObjectTypeSymbol | RuntimeRemoteObjectTypeBigint
   deriving (Ord, Eq, Show, Read)
instance FromJSON RuntimeRemoteObjectType where
   parseJSON = A.withText  "RuntimeRemoteObjectType"  $ \v -> do
      case v of
         "object" -> pure RuntimeRemoteObjectTypeObject
         "function" -> pure RuntimeRemoteObjectTypeFunction
         "undefined" -> pure RuntimeRemoteObjectTypeUndefined
         "string" -> pure RuntimeRemoteObjectTypeString
         "number" -> pure RuntimeRemoteObjectTypeNumber
         "boolean" -> pure RuntimeRemoteObjectTypeBoolean
         "symbol" -> pure RuntimeRemoteObjectTypeSymbol
         "bigint" -> pure RuntimeRemoteObjectTypeBigint
         _ -> fail "failed to parse RuntimeRemoteObjectType"

instance ToJSON RuntimeRemoteObjectType where
   toJSON v = A.String $
      case v of
         RuntimeRemoteObjectTypeObject -> "object"
         RuntimeRemoteObjectTypeFunction -> "function"
         RuntimeRemoteObjectTypeUndefined -> "undefined"
         RuntimeRemoteObjectTypeString -> "string"
         RuntimeRemoteObjectTypeNumber -> "number"
         RuntimeRemoteObjectTypeBoolean -> "boolean"
         RuntimeRemoteObjectTypeSymbol -> "symbol"
         RuntimeRemoteObjectTypeBigint -> "bigint"


data RuntimeRemoteObjectSubtype = RuntimeRemoteObjectSubtypeArray | RuntimeRemoteObjectSubtypeNull | RuntimeRemoteObjectSubtypeNode | RuntimeRemoteObjectSubtypeRegexp | RuntimeRemoteObjectSubtypeDate | RuntimeRemoteObjectSubtypeMap | RuntimeRemoteObjectSubtypeSet | RuntimeRemoteObjectSubtypeWeakmap | RuntimeRemoteObjectSubtypeWeakset | RuntimeRemoteObjectSubtypeIterator | RuntimeRemoteObjectSubtypeGenerator | RuntimeRemoteObjectSubtypeError | RuntimeRemoteObjectSubtypeProxy | RuntimeRemoteObjectSubtypePromise | RuntimeRemoteObjectSubtypeTypedarray | RuntimeRemoteObjectSubtypeArraybuffer | RuntimeRemoteObjectSubtypeDataview | RuntimeRemoteObjectSubtypeWebassemblymemory | RuntimeRemoteObjectSubtypeWasmvalue
   deriving (Ord, Eq, Show, Read)
instance FromJSON RuntimeRemoteObjectSubtype where
   parseJSON = A.withText  "RuntimeRemoteObjectSubtype"  $ \v -> do
      case v of
         "array" -> pure RuntimeRemoteObjectSubtypeArray
         "null" -> pure RuntimeRemoteObjectSubtypeNull
         "node" -> pure RuntimeRemoteObjectSubtypeNode
         "regexp" -> pure RuntimeRemoteObjectSubtypeRegexp
         "date" -> pure RuntimeRemoteObjectSubtypeDate
         "map" -> pure RuntimeRemoteObjectSubtypeMap
         "set" -> pure RuntimeRemoteObjectSubtypeSet
         "weakmap" -> pure RuntimeRemoteObjectSubtypeWeakmap
         "weakset" -> pure RuntimeRemoteObjectSubtypeWeakset
         "iterator" -> pure RuntimeRemoteObjectSubtypeIterator
         "generator" -> pure RuntimeRemoteObjectSubtypeGenerator
         "error" -> pure RuntimeRemoteObjectSubtypeError
         "proxy" -> pure RuntimeRemoteObjectSubtypeProxy
         "promise" -> pure RuntimeRemoteObjectSubtypePromise
         "typedarray" -> pure RuntimeRemoteObjectSubtypeTypedarray
         "arraybuffer" -> pure RuntimeRemoteObjectSubtypeArraybuffer
         "dataview" -> pure RuntimeRemoteObjectSubtypeDataview
         "webassemblymemory" -> pure RuntimeRemoteObjectSubtypeWebassemblymemory
         "wasmvalue" -> pure RuntimeRemoteObjectSubtypeWasmvalue
         _ -> fail "failed to parse RuntimeRemoteObjectSubtype"

instance ToJSON RuntimeRemoteObjectSubtype where
   toJSON v = A.String $
      case v of
         RuntimeRemoteObjectSubtypeArray -> "array"
         RuntimeRemoteObjectSubtypeNull -> "null"
         RuntimeRemoteObjectSubtypeNode -> "node"
         RuntimeRemoteObjectSubtypeRegexp -> "regexp"
         RuntimeRemoteObjectSubtypeDate -> "date"
         RuntimeRemoteObjectSubtypeMap -> "map"
         RuntimeRemoteObjectSubtypeSet -> "set"
         RuntimeRemoteObjectSubtypeWeakmap -> "weakmap"
         RuntimeRemoteObjectSubtypeWeakset -> "weakset"
         RuntimeRemoteObjectSubtypeIterator -> "iterator"
         RuntimeRemoteObjectSubtypeGenerator -> "generator"
         RuntimeRemoteObjectSubtypeError -> "error"
         RuntimeRemoteObjectSubtypeProxy -> "proxy"
         RuntimeRemoteObjectSubtypePromise -> "promise"
         RuntimeRemoteObjectSubtypeTypedarray -> "typedarray"
         RuntimeRemoteObjectSubtypeArraybuffer -> "arraybuffer"
         RuntimeRemoteObjectSubtypeDataview -> "dataview"
         RuntimeRemoteObjectSubtypeWebassemblymemory -> "webassemblymemory"
         RuntimeRemoteObjectSubtypeWasmvalue -> "wasmvalue"



data RuntimeRemoteObject = RuntimeRemoteObject {
  -- | Object type.
  runtimeRemoteObjectType :: RuntimeRemoteObjectType,
  -- | Object subtype hint. Specified for `object` type values only.
  --   NOTE: If you change anything here, make sure to also update
  --   `subtype` in `ObjectPreview` and `PropertyPreview` below.
  runtimeRemoteObjectSubtype :: RuntimeRemoteObjectSubtype,
  -- | Object class (constructor) name. Specified for `object` type values only.
  runtimeRemoteObjectClassName :: Maybe String,
  -- | Remote object value in case of primitive values or JSON values (if it was requested).
  runtimeRemoteObjectValue :: Maybe Int,
  -- | Primitive value which can not be JSON-stringified does not have `value`, but gets this
  --   property.
  runtimeRemoteObjectUnserializableValue :: Maybe RuntimeUnserializableValue,
  -- | String representation of the object.
  runtimeRemoteObjectDescription :: Maybe String,
  -- | WebDriver BiDi representation of the value.
  runtimeRemoteObjectWebDriverValue :: Maybe RuntimeWebDriverValue,
  -- | Unique object identifier (for non-primitive values).
  runtimeRemoteObjectObjectId :: Maybe RuntimeRemoteObjectId,
  -- | Preview containing abbreviated property values. Specified for `object` type values only.
  runtimeRemoteObjectPreview :: Maybe RuntimeObjectPreview,
  runtimeRemoteObjectCustomPreview :: Maybe RuntimeCustomPreview
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeRemoteObject  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 , A.omitNothingFields = True}

instance FromJSON  RuntimeRemoteObject where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }



-- | Type 'Runtime.CustomPreview'.
data RuntimeCustomPreview = RuntimeCustomPreview {
  -- | The JSON-stringified result of formatter.header(object, config) call.
  --   It contains json ML array that represents RemoteObject.
  runtimeCustomPreviewHeader :: String,
  -- | If formatter returns true as a result of formatter.hasBody call then bodyGetterId will
  --   contain RemoteObjectId for the function that returns result of formatter.body(object, config) call.
  --   The result value is json ML array.
  runtimeCustomPreviewBodyGetterId :: Maybe RuntimeRemoteObjectId
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeCustomPreview  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 , A.omitNothingFields = True}

instance FromJSON  RuntimeCustomPreview where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 }



-- | Type 'Runtime.ObjectPreview'.
--   Object containing abbreviated remote object value.
data RuntimeObjectPreviewType = RuntimeObjectPreviewTypeObject | RuntimeObjectPreviewTypeFunction | RuntimeObjectPreviewTypeUndefined | RuntimeObjectPreviewTypeString | RuntimeObjectPreviewTypeNumber | RuntimeObjectPreviewTypeBoolean | RuntimeObjectPreviewTypeSymbol | RuntimeObjectPreviewTypeBigint
   deriving (Ord, Eq, Show, Read)
instance FromJSON RuntimeObjectPreviewType where
   parseJSON = A.withText  "RuntimeObjectPreviewType"  $ \v -> do
      case v of
         "object" -> pure RuntimeObjectPreviewTypeObject
         "function" -> pure RuntimeObjectPreviewTypeFunction
         "undefined" -> pure RuntimeObjectPreviewTypeUndefined
         "string" -> pure RuntimeObjectPreviewTypeString
         "number" -> pure RuntimeObjectPreviewTypeNumber
         "boolean" -> pure RuntimeObjectPreviewTypeBoolean
         "symbol" -> pure RuntimeObjectPreviewTypeSymbol
         "bigint" -> pure RuntimeObjectPreviewTypeBigint
         _ -> fail "failed to parse RuntimeObjectPreviewType"

instance ToJSON RuntimeObjectPreviewType where
   toJSON v = A.String $
      case v of
         RuntimeObjectPreviewTypeObject -> "object"
         RuntimeObjectPreviewTypeFunction -> "function"
         RuntimeObjectPreviewTypeUndefined -> "undefined"
         RuntimeObjectPreviewTypeString -> "string"
         RuntimeObjectPreviewTypeNumber -> "number"
         RuntimeObjectPreviewTypeBoolean -> "boolean"
         RuntimeObjectPreviewTypeSymbol -> "symbol"
         RuntimeObjectPreviewTypeBigint -> "bigint"


data RuntimeObjectPreviewSubtype = RuntimeObjectPreviewSubtypeArray | RuntimeObjectPreviewSubtypeNull | RuntimeObjectPreviewSubtypeNode | RuntimeObjectPreviewSubtypeRegexp | RuntimeObjectPreviewSubtypeDate | RuntimeObjectPreviewSubtypeMap | RuntimeObjectPreviewSubtypeSet | RuntimeObjectPreviewSubtypeWeakmap | RuntimeObjectPreviewSubtypeWeakset | RuntimeObjectPreviewSubtypeIterator | RuntimeObjectPreviewSubtypeGenerator | RuntimeObjectPreviewSubtypeError | RuntimeObjectPreviewSubtypeProxy | RuntimeObjectPreviewSubtypePromise | RuntimeObjectPreviewSubtypeTypedarray | RuntimeObjectPreviewSubtypeArraybuffer | RuntimeObjectPreviewSubtypeDataview | RuntimeObjectPreviewSubtypeWebassemblymemory | RuntimeObjectPreviewSubtypeWasmvalue
   deriving (Ord, Eq, Show, Read)
instance FromJSON RuntimeObjectPreviewSubtype where
   parseJSON = A.withText  "RuntimeObjectPreviewSubtype"  $ \v -> do
      case v of
         "array" -> pure RuntimeObjectPreviewSubtypeArray
         "null" -> pure RuntimeObjectPreviewSubtypeNull
         "node" -> pure RuntimeObjectPreviewSubtypeNode
         "regexp" -> pure RuntimeObjectPreviewSubtypeRegexp
         "date" -> pure RuntimeObjectPreviewSubtypeDate
         "map" -> pure RuntimeObjectPreviewSubtypeMap
         "set" -> pure RuntimeObjectPreviewSubtypeSet
         "weakmap" -> pure RuntimeObjectPreviewSubtypeWeakmap
         "weakset" -> pure RuntimeObjectPreviewSubtypeWeakset
         "iterator" -> pure RuntimeObjectPreviewSubtypeIterator
         "generator" -> pure RuntimeObjectPreviewSubtypeGenerator
         "error" -> pure RuntimeObjectPreviewSubtypeError
         "proxy" -> pure RuntimeObjectPreviewSubtypeProxy
         "promise" -> pure RuntimeObjectPreviewSubtypePromise
         "typedarray" -> pure RuntimeObjectPreviewSubtypeTypedarray
         "arraybuffer" -> pure RuntimeObjectPreviewSubtypeArraybuffer
         "dataview" -> pure RuntimeObjectPreviewSubtypeDataview
         "webassemblymemory" -> pure RuntimeObjectPreviewSubtypeWebassemblymemory
         "wasmvalue" -> pure RuntimeObjectPreviewSubtypeWasmvalue
         _ -> fail "failed to parse RuntimeObjectPreviewSubtype"

instance ToJSON RuntimeObjectPreviewSubtype where
   toJSON v = A.String $
      case v of
         RuntimeObjectPreviewSubtypeArray -> "array"
         RuntimeObjectPreviewSubtypeNull -> "null"
         RuntimeObjectPreviewSubtypeNode -> "node"
         RuntimeObjectPreviewSubtypeRegexp -> "regexp"
         RuntimeObjectPreviewSubtypeDate -> "date"
         RuntimeObjectPreviewSubtypeMap -> "map"
         RuntimeObjectPreviewSubtypeSet -> "set"
         RuntimeObjectPreviewSubtypeWeakmap -> "weakmap"
         RuntimeObjectPreviewSubtypeWeakset -> "weakset"
         RuntimeObjectPreviewSubtypeIterator -> "iterator"
         RuntimeObjectPreviewSubtypeGenerator -> "generator"
         RuntimeObjectPreviewSubtypeError -> "error"
         RuntimeObjectPreviewSubtypeProxy -> "proxy"
         RuntimeObjectPreviewSubtypePromise -> "promise"
         RuntimeObjectPreviewSubtypeTypedarray -> "typedarray"
         RuntimeObjectPreviewSubtypeArraybuffer -> "arraybuffer"
         RuntimeObjectPreviewSubtypeDataview -> "dataview"
         RuntimeObjectPreviewSubtypeWebassemblymemory -> "webassemblymemory"
         RuntimeObjectPreviewSubtypeWasmvalue -> "wasmvalue"



data RuntimeObjectPreview = RuntimeObjectPreview {
  -- | Object type.
  runtimeObjectPreviewType :: RuntimeObjectPreviewType,
  -- | Object subtype hint. Specified for `object` type values only.
  runtimeObjectPreviewSubtype :: RuntimeObjectPreviewSubtype,
  -- | String representation of the object.
  runtimeObjectPreviewDescription :: Maybe String,
  -- | True iff some of the properties or entries of the original object did not fit.
  runtimeObjectPreviewOverflow :: Bool,
  -- | List of the properties.
  runtimeObjectPreviewProperties :: [RuntimePropertyPreview],
  -- | List of the entries. Specified for `map` and `set` subtype values only.
  runtimeObjectPreviewEntries :: Maybe [RuntimeEntryPreview]
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeObjectPreview  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 , A.omitNothingFields = True}

instance FromJSON  RuntimeObjectPreview where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 }



-- | Type 'Runtime.PropertyPreview'.
data RuntimePropertyPreviewType = RuntimePropertyPreviewTypeObject | RuntimePropertyPreviewTypeFunction | RuntimePropertyPreviewTypeUndefined | RuntimePropertyPreviewTypeString | RuntimePropertyPreviewTypeNumber | RuntimePropertyPreviewTypeBoolean | RuntimePropertyPreviewTypeSymbol | RuntimePropertyPreviewTypeAccessor | RuntimePropertyPreviewTypeBigint
   deriving (Ord, Eq, Show, Read)
instance FromJSON RuntimePropertyPreviewType where
   parseJSON = A.withText  "RuntimePropertyPreviewType"  $ \v -> do
      case v of
         "object" -> pure RuntimePropertyPreviewTypeObject
         "function" -> pure RuntimePropertyPreviewTypeFunction
         "undefined" -> pure RuntimePropertyPreviewTypeUndefined
         "string" -> pure RuntimePropertyPreviewTypeString
         "number" -> pure RuntimePropertyPreviewTypeNumber
         "boolean" -> pure RuntimePropertyPreviewTypeBoolean
         "symbol" -> pure RuntimePropertyPreviewTypeSymbol
         "accessor" -> pure RuntimePropertyPreviewTypeAccessor
         "bigint" -> pure RuntimePropertyPreviewTypeBigint
         _ -> fail "failed to parse RuntimePropertyPreviewType"

instance ToJSON RuntimePropertyPreviewType where
   toJSON v = A.String $
      case v of
         RuntimePropertyPreviewTypeObject -> "object"
         RuntimePropertyPreviewTypeFunction -> "function"
         RuntimePropertyPreviewTypeUndefined -> "undefined"
         RuntimePropertyPreviewTypeString -> "string"
         RuntimePropertyPreviewTypeNumber -> "number"
         RuntimePropertyPreviewTypeBoolean -> "boolean"
         RuntimePropertyPreviewTypeSymbol -> "symbol"
         RuntimePropertyPreviewTypeAccessor -> "accessor"
         RuntimePropertyPreviewTypeBigint -> "bigint"


data RuntimePropertyPreviewSubtype = RuntimePropertyPreviewSubtypeArray | RuntimePropertyPreviewSubtypeNull | RuntimePropertyPreviewSubtypeNode | RuntimePropertyPreviewSubtypeRegexp | RuntimePropertyPreviewSubtypeDate | RuntimePropertyPreviewSubtypeMap | RuntimePropertyPreviewSubtypeSet | RuntimePropertyPreviewSubtypeWeakmap | RuntimePropertyPreviewSubtypeWeakset | RuntimePropertyPreviewSubtypeIterator | RuntimePropertyPreviewSubtypeGenerator | RuntimePropertyPreviewSubtypeError | RuntimePropertyPreviewSubtypeProxy | RuntimePropertyPreviewSubtypePromise | RuntimePropertyPreviewSubtypeTypedarray | RuntimePropertyPreviewSubtypeArraybuffer | RuntimePropertyPreviewSubtypeDataview | RuntimePropertyPreviewSubtypeWebassemblymemory | RuntimePropertyPreviewSubtypeWasmvalue
   deriving (Ord, Eq, Show, Read)
instance FromJSON RuntimePropertyPreviewSubtype where
   parseJSON = A.withText  "RuntimePropertyPreviewSubtype"  $ \v -> do
      case v of
         "array" -> pure RuntimePropertyPreviewSubtypeArray
         "null" -> pure RuntimePropertyPreviewSubtypeNull
         "node" -> pure RuntimePropertyPreviewSubtypeNode
         "regexp" -> pure RuntimePropertyPreviewSubtypeRegexp
         "date" -> pure RuntimePropertyPreviewSubtypeDate
         "map" -> pure RuntimePropertyPreviewSubtypeMap
         "set" -> pure RuntimePropertyPreviewSubtypeSet
         "weakmap" -> pure RuntimePropertyPreviewSubtypeWeakmap
         "weakset" -> pure RuntimePropertyPreviewSubtypeWeakset
         "iterator" -> pure RuntimePropertyPreviewSubtypeIterator
         "generator" -> pure RuntimePropertyPreviewSubtypeGenerator
         "error" -> pure RuntimePropertyPreviewSubtypeError
         "proxy" -> pure RuntimePropertyPreviewSubtypeProxy
         "promise" -> pure RuntimePropertyPreviewSubtypePromise
         "typedarray" -> pure RuntimePropertyPreviewSubtypeTypedarray
         "arraybuffer" -> pure RuntimePropertyPreviewSubtypeArraybuffer
         "dataview" -> pure RuntimePropertyPreviewSubtypeDataview
         "webassemblymemory" -> pure RuntimePropertyPreviewSubtypeWebassemblymemory
         "wasmvalue" -> pure RuntimePropertyPreviewSubtypeWasmvalue
         _ -> fail "failed to parse RuntimePropertyPreviewSubtype"

instance ToJSON RuntimePropertyPreviewSubtype where
   toJSON v = A.String $
      case v of
         RuntimePropertyPreviewSubtypeArray -> "array"
         RuntimePropertyPreviewSubtypeNull -> "null"
         RuntimePropertyPreviewSubtypeNode -> "node"
         RuntimePropertyPreviewSubtypeRegexp -> "regexp"
         RuntimePropertyPreviewSubtypeDate -> "date"
         RuntimePropertyPreviewSubtypeMap -> "map"
         RuntimePropertyPreviewSubtypeSet -> "set"
         RuntimePropertyPreviewSubtypeWeakmap -> "weakmap"
         RuntimePropertyPreviewSubtypeWeakset -> "weakset"
         RuntimePropertyPreviewSubtypeIterator -> "iterator"
         RuntimePropertyPreviewSubtypeGenerator -> "generator"
         RuntimePropertyPreviewSubtypeError -> "error"
         RuntimePropertyPreviewSubtypeProxy -> "proxy"
         RuntimePropertyPreviewSubtypePromise -> "promise"
         RuntimePropertyPreviewSubtypeTypedarray -> "typedarray"
         RuntimePropertyPreviewSubtypeArraybuffer -> "arraybuffer"
         RuntimePropertyPreviewSubtypeDataview -> "dataview"
         RuntimePropertyPreviewSubtypeWebassemblymemory -> "webassemblymemory"
         RuntimePropertyPreviewSubtypeWasmvalue -> "wasmvalue"



data RuntimePropertyPreview = RuntimePropertyPreview {
  -- | Property name.
  runtimePropertyPreviewName :: String,
  -- | Object type. Accessor means that the property itself is an accessor property.
  runtimePropertyPreviewType :: RuntimePropertyPreviewType,
  -- | User-friendly property value string.
  runtimePropertyPreviewValue :: Maybe String,
  -- | Nested value preview.
  runtimePropertyPreviewValuePreview :: Maybe RuntimeObjectPreview,
  -- | Object subtype hint. Specified for `object` type values only.
  runtimePropertyPreviewSubtype :: RuntimePropertyPreviewSubtype
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimePropertyPreview  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 , A.omitNothingFields = True}

instance FromJSON  RuntimePropertyPreview where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 }



-- | Type 'Runtime.EntryPreview'.
data RuntimeEntryPreview = RuntimeEntryPreview {
  -- | Preview of the key. Specified for map-like collection entries.
  runtimeEntryPreviewKey :: Maybe RuntimeObjectPreview,
  -- | Preview of the value.
  runtimeEntryPreviewValue :: RuntimeObjectPreview
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeEntryPreview  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 , A.omitNothingFields = True}

instance FromJSON  RuntimeEntryPreview where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }



-- | Type 'Runtime.PropertyDescriptor'.
--   Object property descriptor.
data RuntimePropertyDescriptor = RuntimePropertyDescriptor {
  -- | Property name or symbol description.
  runtimePropertyDescriptorName :: String,
  -- | The value associated with the property.
  runtimePropertyDescriptorValue :: Maybe RuntimeRemoteObject,
  -- | True if the value associated with the property may be changed (data descriptors only).
  runtimePropertyDescriptorWritable :: Maybe Bool,
  -- | A function which serves as a getter for the property, or `undefined` if there is no getter
  --   (accessor descriptors only).
  runtimePropertyDescriptorGet :: Maybe RuntimeRemoteObject,
  -- | A function which serves as a setter for the property, or `undefined` if there is no setter
  --   (accessor descriptors only).
  runtimePropertyDescriptorSet :: Maybe RuntimeRemoteObject,
  -- | True if the type of this property descriptor may be changed and if the property may be
  --   deleted from the corresponding object.
  runtimePropertyDescriptorConfigurable :: Bool,
  -- | True if this property shows up during enumeration of the properties on the corresponding
  --   object.
  runtimePropertyDescriptorEnumerable :: Bool,
  -- | True if the result was thrown during the evaluation.
  runtimePropertyDescriptorWasThrown :: Maybe Bool,
  -- | True if the property is owned for the object.
  runtimePropertyDescriptorIsOwn :: Maybe Bool,
  -- | Property symbol object, if the property is of the `symbol` type.
  runtimePropertyDescriptorSymbol :: Maybe RuntimeRemoteObject
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimePropertyDescriptor  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 25 , A.omitNothingFields = True}

instance FromJSON  RuntimePropertyDescriptor where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 25 }



-- | Type 'Runtime.InternalPropertyDescriptor'.
--   Object internal property descriptor. This property isn't normally visible in JavaScript code.
data RuntimeInternalPropertyDescriptor = RuntimeInternalPropertyDescriptor {
  -- | Conventional property name.
  runtimeInternalPropertyDescriptorName :: String,
  -- | The value associated with the property.
  runtimeInternalPropertyDescriptorValue :: Maybe RuntimeRemoteObject
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeInternalPropertyDescriptor  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 , A.omitNothingFields = True}

instance FromJSON  RuntimeInternalPropertyDescriptor where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 33 }



-- | Type 'Runtime.PrivatePropertyDescriptor'.
--   Object private field descriptor.
data RuntimePrivatePropertyDescriptor = RuntimePrivatePropertyDescriptor {
  -- | Private property name.
  runtimePrivatePropertyDescriptorName :: String,
  -- | The value associated with the private property.
  runtimePrivatePropertyDescriptorValue :: Maybe RuntimeRemoteObject,
  -- | A function which serves as a getter for the private property,
  --   or `undefined` if there is no getter (accessor descriptors only).
  runtimePrivatePropertyDescriptorGet :: Maybe RuntimeRemoteObject,
  -- | A function which serves as a setter for the private property,
  --   or `undefined` if there is no setter (accessor descriptors only).
  runtimePrivatePropertyDescriptorSet :: Maybe RuntimeRemoteObject
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimePrivatePropertyDescriptor  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 , A.omitNothingFields = True}

instance FromJSON  RuntimePrivatePropertyDescriptor where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 }



-- | Type 'Runtime.CallArgument'.
--   Represents function call argument. Either remote object id `objectId`, primitive `value`,
--   unserializable primitive value or neither of (for undefined) them should be specified.
data RuntimeCallArgument = RuntimeCallArgument {
  -- | Primitive value or serializable javascript object.
  runtimeCallArgumentValue :: Maybe Int,
  -- | Primitive value which can not be JSON-stringified.
  runtimeCallArgumentUnserializableValue :: Maybe RuntimeUnserializableValue,
  -- | Remote object handle.
  runtimeCallArgumentObjectId :: Maybe RuntimeRemoteObjectId
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeCallArgument  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 , A.omitNothingFields = True}

instance FromJSON  RuntimeCallArgument where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }



-- | Type 'Runtime.ExecutionContextId'.
--   Id of an execution context.
type RuntimeExecutionContextId = Int

-- | Type 'Runtime.ExecutionContextDescription'.
--   Description of an isolated world.
data RuntimeExecutionContextDescription = RuntimeExecutionContextDescription {
  -- | Unique id of the execution context. It can be used to specify in which execution context
  --   script evaluation should be performed.
  runtimeExecutionContextDescriptionId :: RuntimeExecutionContextId,
  -- | Execution context origin.
  runtimeExecutionContextDescriptionOrigin :: String,
  -- | Human readable name describing given context.
  runtimeExecutionContextDescriptionName :: String,
  -- | A system-unique execution context identifier. Unlike the id, this is unique across
  --   multiple processes, so can be reliably used to identify specific context while backend
  --   performs a cross-process navigation.
  runtimeExecutionContextDescriptionUniqueId :: String,
  -- | Embedder-specific auxiliary data.
  runtimeExecutionContextDescriptionAuxData :: Maybe [(String, String)]
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeExecutionContextDescription  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 34 , A.omitNothingFields = True}

instance FromJSON  RuntimeExecutionContextDescription where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 34 }



-- | Type 'Runtime.ExceptionDetails'.
--   Detailed information about exception (or error) that was thrown during script compilation or
--   execution.
data RuntimeExceptionDetails = RuntimeExceptionDetails {
  -- | Exception id.
  runtimeExceptionDetailsExceptionId :: Int,
  -- | Exception text, which should be used together with exception object when available.
  runtimeExceptionDetailsText :: String,
  -- | Line number of the exception location (0-based).
  runtimeExceptionDetailsLineNumber :: Int,
  -- | Column number of the exception location (0-based).
  runtimeExceptionDetailsColumnNumber :: Int,
  -- | Script ID of the exception location.
  runtimeExceptionDetailsScriptId :: Maybe RuntimeScriptId,
  -- | URL of the exception location, to be used when the script was not reported.
  runtimeExceptionDetailsUrl :: Maybe String,
  -- | JavaScript stack trace if available.
  runtimeExceptionDetailsStackTrace :: Maybe RuntimeStackTrace,
  -- | Exception object if available.
  runtimeExceptionDetailsException :: Maybe RuntimeRemoteObject,
  -- | Identifier of the context where exception happened.
  runtimeExceptionDetailsExecutionContextId :: Maybe RuntimeExecutionContextId,
  -- | Dictionary with entries of meta data that the client associated
  --   with this exception, such as information about associated network
  --   requests, etc.
  runtimeExceptionDetailsExceptionMetaData :: Maybe [(String, String)]
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeExceptionDetails  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 , A.omitNothingFields = True}

instance FromJSON  RuntimeExceptionDetails where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 }



-- | Type 'Runtime.Timestamp'.
--   Number of milliseconds since epoch.
type RuntimeTimestamp = Double

-- | Type 'Runtime.TimeDelta'.
--   Number of milliseconds.
type RuntimeTimeDelta = Double

-- | Type 'Runtime.CallFrame'.
--   Stack entry for runtime errors and assertions.
data RuntimeCallFrame = RuntimeCallFrame {
  -- | JavaScript function name.
  runtimeCallFrameFunctionName :: String,
  -- | JavaScript script id.
  runtimeCallFrameScriptId :: RuntimeScriptId,
  -- | JavaScript script name or url.
  runtimeCallFrameUrl :: String,
  -- | JavaScript script line number (0-based).
  runtimeCallFrameLineNumber :: Int,
  -- | JavaScript script column number (0-based).
  runtimeCallFrameColumnNumber :: Int
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeCallFrame  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 , A.omitNothingFields = True}

instance FromJSON  RuntimeCallFrame where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 }



-- | Type 'Runtime.StackTrace'.
--   Call frames for assertions or error messages.
data RuntimeStackTrace = RuntimeStackTrace {
  -- | String label of this stack trace. For async traces this may be a name of the function that
  --   initiated the async call.
  runtimeStackTraceDescription :: Maybe String,
  -- | JavaScript function name.
  runtimeStackTraceCallFrames :: [RuntimeCallFrame],
  -- | Asynchronous JavaScript stack trace that preceded this stack, if available.
  runtimeStackTraceParent :: Maybe RuntimeStackTrace,
  -- | Asynchronous JavaScript stack trace that preceded this stack, if available.
  runtimeStackTraceParentId :: Maybe RuntimeStackTraceId
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeStackTrace  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 , A.omitNothingFields = True}

instance FromJSON  RuntimeStackTrace where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 }



-- | Type 'Runtime.UniqueDebuggerId'.
--   Unique identifier of current debugger.
type RuntimeUniqueDebuggerId = String

-- | Type 'Runtime.StackTraceId'.
--   If `debuggerId` is set stack trace comes from another debugger and can be resolved there. This
--   allows to track cross-debugger calls. See `Runtime.StackTrace` and `Debugger.paused` for usages.
data RuntimeStackTraceId = RuntimeStackTraceId {
  runtimeStackTraceIdId :: String,
  runtimeStackTraceIdDebuggerId :: Maybe RuntimeUniqueDebuggerId
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeStackTraceId  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 , A.omitNothingFields = True}

instance FromJSON  RuntimeStackTraceId where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }





-- | Type of the 'Runtime.bindingCalled' event.
data RuntimeBindingCalled = RuntimeBindingCalled {
  runtimeBindingCalledName :: String,
  runtimeBindingCalledPayload :: String,
  -- | Identifier of the context where the call was made.
  runtimeBindingCalledExecutionContextId :: RuntimeExecutionContextId
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeBindingCalled  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 , A.omitNothingFields = True}

instance FromJSON  RuntimeBindingCalled where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 }


instance Event RuntimeBindingCalled where
    eventName _ = "Runtime.bindingCalled"

-- | Type of the 'Runtime.consoleAPICalled' event.
data RuntimeConsoleAPICalledType = RuntimeConsoleAPICalledTypeLog | RuntimeConsoleAPICalledTypeDebug | RuntimeConsoleAPICalledTypeInfo | RuntimeConsoleAPICalledTypeError | RuntimeConsoleAPICalledTypeWarning | RuntimeConsoleAPICalledTypeDir | RuntimeConsoleAPICalledTypeDirxml | RuntimeConsoleAPICalledTypeTable | RuntimeConsoleAPICalledTypeTrace | RuntimeConsoleAPICalledTypeClear | RuntimeConsoleAPICalledTypeStartGroup | RuntimeConsoleAPICalledTypeStartGroupCollapsed | RuntimeConsoleAPICalledTypeEndGroup | RuntimeConsoleAPICalledTypeAssert | RuntimeConsoleAPICalledTypeProfile | RuntimeConsoleAPICalledTypeProfileEnd | RuntimeConsoleAPICalledTypeCount | RuntimeConsoleAPICalledTypeTimeEnd
   deriving (Ord, Eq, Show, Read)
instance FromJSON RuntimeConsoleAPICalledType where
   parseJSON = A.withText  "RuntimeConsoleAPICalledType"  $ \v -> do
      case v of
         "log" -> pure RuntimeConsoleAPICalledTypeLog
         "debug" -> pure RuntimeConsoleAPICalledTypeDebug
         "info" -> pure RuntimeConsoleAPICalledTypeInfo
         "error" -> pure RuntimeConsoleAPICalledTypeError
         "warning" -> pure RuntimeConsoleAPICalledTypeWarning
         "dir" -> pure RuntimeConsoleAPICalledTypeDir
         "dirxml" -> pure RuntimeConsoleAPICalledTypeDirxml
         "table" -> pure RuntimeConsoleAPICalledTypeTable
         "trace" -> pure RuntimeConsoleAPICalledTypeTrace
         "clear" -> pure RuntimeConsoleAPICalledTypeClear
         "startGroup" -> pure RuntimeConsoleAPICalledTypeStartGroup
         "startGroupCollapsed" -> pure RuntimeConsoleAPICalledTypeStartGroupCollapsed
         "endGroup" -> pure RuntimeConsoleAPICalledTypeEndGroup
         "assert" -> pure RuntimeConsoleAPICalledTypeAssert
         "profile" -> pure RuntimeConsoleAPICalledTypeProfile
         "profileEnd" -> pure RuntimeConsoleAPICalledTypeProfileEnd
         "count" -> pure RuntimeConsoleAPICalledTypeCount
         "timeEnd" -> pure RuntimeConsoleAPICalledTypeTimeEnd
         _ -> fail "failed to parse RuntimeConsoleAPICalledType"

instance ToJSON RuntimeConsoleAPICalledType where
   toJSON v = A.String $
      case v of
         RuntimeConsoleAPICalledTypeLog -> "log"
         RuntimeConsoleAPICalledTypeDebug -> "debug"
         RuntimeConsoleAPICalledTypeInfo -> "info"
         RuntimeConsoleAPICalledTypeError -> "error"
         RuntimeConsoleAPICalledTypeWarning -> "warning"
         RuntimeConsoleAPICalledTypeDir -> "dir"
         RuntimeConsoleAPICalledTypeDirxml -> "dirxml"
         RuntimeConsoleAPICalledTypeTable -> "table"
         RuntimeConsoleAPICalledTypeTrace -> "trace"
         RuntimeConsoleAPICalledTypeClear -> "clear"
         RuntimeConsoleAPICalledTypeStartGroup -> "startGroup"
         RuntimeConsoleAPICalledTypeStartGroupCollapsed -> "startGroupCollapsed"
         RuntimeConsoleAPICalledTypeEndGroup -> "endGroup"
         RuntimeConsoleAPICalledTypeAssert -> "assert"
         RuntimeConsoleAPICalledTypeProfile -> "profile"
         RuntimeConsoleAPICalledTypeProfileEnd -> "profileEnd"
         RuntimeConsoleAPICalledTypeCount -> "count"
         RuntimeConsoleAPICalledTypeTimeEnd -> "timeEnd"



data RuntimeConsoleAPICalled = RuntimeConsoleAPICalled {
  -- | Type of the call.
  runtimeConsoleAPICalledType :: RuntimeConsoleAPICalledType,
  -- | Call arguments.
  runtimeConsoleAPICalledArgs :: [RuntimeRemoteObject],
  -- | Identifier of the context where the call was made.
  runtimeConsoleAPICalledExecutionContextId :: RuntimeExecutionContextId,
  -- | Call timestamp.
  runtimeConsoleAPICalledTimestamp :: RuntimeTimestamp,
  -- | Stack trace captured when the call was made. The async stack chain is automatically reported for
  --   the following call types: `assert`, `error`, `trace`, `warning`. For other types the async call
  --   chain can be retrieved using `Debugger.getStackTrace` and `stackTrace.parentId` field.
  runtimeConsoleAPICalledStackTrace :: Maybe RuntimeStackTrace,
  -- | Console context descriptor for calls on non-default console context (not console.*):
  --   'anonymous#unique-logger-id' for call on unnamed context, 'name#unique-logger-id' for call
  --   on named context.
  runtimeConsoleAPICalledContext :: Maybe String
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeConsoleAPICalled  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 , A.omitNothingFields = True}

instance FromJSON  RuntimeConsoleAPICalled where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 }


instance Event RuntimeConsoleAPICalled where
    eventName _ = "Runtime.consoleAPICalled"

-- | Type of the 'Runtime.exceptionRevoked' event.
data RuntimeExceptionRevoked = RuntimeExceptionRevoked {
  -- | Reason describing why exception was revoked.
  runtimeExceptionRevokedReason :: String,
  -- | The id of revoked exception, as reported in `exceptionThrown`.
  runtimeExceptionRevokedExceptionId :: Int
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeExceptionRevoked  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 , A.omitNothingFields = True}

instance FromJSON  RuntimeExceptionRevoked where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 }


instance Event RuntimeExceptionRevoked where
    eventName _ = "Runtime.exceptionRevoked"

-- | Type of the 'Runtime.exceptionThrown' event.
data RuntimeExceptionThrown = RuntimeExceptionThrown {
  -- | Timestamp of the exception.
  runtimeExceptionThrownTimestamp :: RuntimeTimestamp,
  runtimeExceptionThrownExceptionDetails :: RuntimeExceptionDetails
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeExceptionThrown  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 , A.omitNothingFields = True}

instance FromJSON  RuntimeExceptionThrown where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 }


instance Event RuntimeExceptionThrown where
    eventName _ = "Runtime.exceptionThrown"

-- | Type of the 'Runtime.executionContextCreated' event.
data RuntimeExecutionContextCreated = RuntimeExecutionContextCreated {
  -- | A newly created execution context.
  runtimeExecutionContextCreatedContext :: RuntimeExecutionContextDescription
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeExecutionContextCreated  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 , A.omitNothingFields = True}

instance FromJSON  RuntimeExecutionContextCreated where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }


instance Event RuntimeExecutionContextCreated where
    eventName _ = "Runtime.executionContextCreated"

-- | Type of the 'Runtime.executionContextDestroyed' event.
data RuntimeExecutionContextDestroyed = RuntimeExecutionContextDestroyed {
  -- | Id of the destroyed context
  runtimeExecutionContextDestroyedExecutionContextId :: RuntimeExecutionContextId
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeExecutionContextDestroyed  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 , A.omitNothingFields = True}

instance FromJSON  RuntimeExecutionContextDestroyed where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 32 }


instance Event RuntimeExecutionContextDestroyed where
    eventName _ = "Runtime.executionContextDestroyed"

-- | Type of the 'Runtime.executionContextsCleared' event.
data RuntimeExecutionContextsCleared = RuntimeExecutionContextsCleared
   deriving (Eq, Show, Read)
instance FromJSON RuntimeExecutionContextsCleared where
   parseJSON = A.withText  "RuntimeExecutionContextsCleared"  $ \v -> do
      case v of
         "RuntimeExecutionContextsCleared" -> pure RuntimeExecutionContextsCleared
         _ -> fail "failed to parse RuntimeExecutionContextsCleared"


instance Event RuntimeExecutionContextsCleared where
    eventName _ = "Runtime.executionContextsCleared"

-- | Type of the 'Runtime.inspectRequested' event.
data RuntimeInspectRequested = RuntimeInspectRequested {
  runtimeInspectRequestedObject :: RuntimeRemoteObject,
  runtimeInspectRequestedHints :: [(String, String)],
  -- | Identifier of the context where the call was made.
  runtimeInspectRequestedExecutionContextId :: Maybe RuntimeExecutionContextId
} deriving (Generic, Eq, Show, Read)
instance ToJSON RuntimeInspectRequested  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 , A.omitNothingFields = True}

instance FromJSON  RuntimeInspectRequested where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 23 }


instance Event RuntimeInspectRequested where
    eventName _ = "Runtime.inspectRequested"



-- | Parameters of the 'runtimeAwaitPromise' command.
data PRuntimeAwaitPromise = PRuntimeAwaitPromise {
  -- | Identifier of the promise.
  pRuntimeAwaitPromisePromiseObjectId :: RuntimeRemoteObjectId,
  -- | Whether the result is expected to be a JSON object that should be sent by value.
  pRuntimeAwaitPromiseReturnByValue :: Maybe Bool,
  -- | Whether preview should be generated for the result.
  pRuntimeAwaitPromiseGeneratePreview :: Maybe Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeAwaitPromise  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 , A.omitNothingFields = True}

instance FromJSON  PRuntimeAwaitPromise where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 }


-- | Function for the 'Runtime.awaitPromise' command.
--   Add handler to promise with given promise object id.
--   Returns: 'PRuntimeAwaitPromise'
--   Returns: 'RuntimeAwaitPromise'
runtimeAwaitPromise :: Handle -> PRuntimeAwaitPromise -> IO RuntimeAwaitPromise
runtimeAwaitPromise handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeAwaitPromise' command.
data RuntimeAwaitPromise = RuntimeAwaitPromise {
  -- | Promise result. Will contain rejected value if promise was rejected.
  runtimeAwaitPromiseResult :: RuntimeRemoteObject,
  -- | Exception details if stack strace is available.
  runtimeAwaitPromiseExceptionDetails :: Maybe RuntimeExceptionDetails
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeAwaitPromise where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }

instance Command PRuntimeAwaitPromise where
    type CommandResponse PRuntimeAwaitPromise = RuntimeAwaitPromise
    commandName _ = "Runtime.awaitPromise"


-- | Parameters of the 'runtimeCallFunctionOn' command.
data PRuntimeCallFunctionOn = PRuntimeCallFunctionOn {
  -- | Declaration of the function to call.
  pRuntimeCallFunctionOnFunctionDeclaration :: String,
  -- | Identifier of the object to call function on. Either objectId or executionContextId should
  --   be specified.
  pRuntimeCallFunctionOnObjectId :: Maybe RuntimeRemoteObjectId,
  -- | Call arguments. All call arguments must belong to the same JavaScript world as the target
  --   object.
  pRuntimeCallFunctionOnArguments :: Maybe [RuntimeCallArgument],
  -- | In silent mode exceptions thrown during evaluation are not reported and do not pause
  --   execution. Overrides `setPauseOnException` state.
  pRuntimeCallFunctionOnSilent :: Maybe Bool,
  -- | Whether the result is expected to be a JSON object which should be sent by value.
  pRuntimeCallFunctionOnReturnByValue :: Maybe Bool,
  -- | Whether preview should be generated for the result.
  pRuntimeCallFunctionOnGeneratePreview :: Maybe Bool,
  -- | Whether execution should be treated as initiated by user in the UI.
  pRuntimeCallFunctionOnUserGesture :: Maybe Bool,
  -- | Whether execution should `await` for resulting value and return once awaited promise is
  --   resolved.
  pRuntimeCallFunctionOnAwaitPromise :: Maybe Bool,
  -- | Specifies execution context which global object will be used to call function on. Either
  --   executionContextId or objectId should be specified.
  pRuntimeCallFunctionOnExecutionContextId :: Maybe RuntimeExecutionContextId,
  -- | Symbolic group name that can be used to release multiple objects. If objectGroup is not
  --   specified and objectId is, objectGroup will be inherited from object.
  pRuntimeCallFunctionOnObjectGroup :: Maybe String,
  -- | Whether to throw an exception if side effect cannot be ruled out during evaluation.
  pRuntimeCallFunctionOnThrowOnSideEffect :: Maybe Bool,
  -- | Whether the result should contain `webDriverValue`, serialized according to
  --   https://w3c.github.io/webdriver-bidi. This is mutually exclusive with `returnByValue`, but
  --   resulting `objectId` is still provided.
  pRuntimeCallFunctionOnGenerateWebDriverValue :: Maybe Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeCallFunctionOn  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 , A.omitNothingFields = True}

instance FromJSON  PRuntimeCallFunctionOn where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 22 }


-- | Function for the 'Runtime.callFunctionOn' command.
--   Calls function with given declaration on the given object. Object group of the result is
--   inherited from the target object.
--   Returns: 'PRuntimeCallFunctionOn'
--   Returns: 'RuntimeCallFunctionOn'
runtimeCallFunctionOn :: Handle -> PRuntimeCallFunctionOn -> IO RuntimeCallFunctionOn
runtimeCallFunctionOn handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeCallFunctionOn' command.
data RuntimeCallFunctionOn = RuntimeCallFunctionOn {
  -- | Call result.
  runtimeCallFunctionOnResult :: RuntimeRemoteObject,
  -- | Exception details.
  runtimeCallFunctionOnExceptionDetails :: Maybe RuntimeExceptionDetails
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeCallFunctionOn where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 }

instance Command PRuntimeCallFunctionOn where
    type CommandResponse PRuntimeCallFunctionOn = RuntimeCallFunctionOn
    commandName _ = "Runtime.callFunctionOn"


-- | Parameters of the 'runtimeCompileScript' command.
data PRuntimeCompileScript = PRuntimeCompileScript {
  -- | Expression to compile.
  pRuntimeCompileScriptExpression :: String,
  -- | Source url to be set for the script.
  pRuntimeCompileScriptSourceURL :: String,
  -- | Specifies whether the compiled script should be persisted.
  pRuntimeCompileScriptPersistScript :: Bool,
  -- | Specifies in which execution context to perform script run. If the parameter is omitted the
  --   evaluation will be performed in the context of the inspected page.
  pRuntimeCompileScriptExecutionContextId :: Maybe RuntimeExecutionContextId
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeCompileScript  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 , A.omitNothingFields = True}

instance FromJSON  PRuntimeCompileScript where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 }


-- | Function for the 'Runtime.compileScript' command.
--   Compiles expression.
--   Returns: 'PRuntimeCompileScript'
--   Returns: 'RuntimeCompileScript'
runtimeCompileScript :: Handle -> PRuntimeCompileScript -> IO RuntimeCompileScript
runtimeCompileScript handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeCompileScript' command.
data RuntimeCompileScript = RuntimeCompileScript {
  -- | Id of the script.
  runtimeCompileScriptScriptId :: Maybe RuntimeScriptId,
  -- | Exception details.
  runtimeCompileScriptExceptionDetails :: Maybe RuntimeExceptionDetails
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeCompileScript where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 }

instance Command PRuntimeCompileScript where
    type CommandResponse PRuntimeCompileScript = RuntimeCompileScript
    commandName _ = "Runtime.compileScript"


-- | Parameters of the 'runtimeDisable' command.
data PRuntimeDisable = PRuntimeDisable
instance ToJSON PRuntimeDisable where toJSON _ = A.Null

-- | Function for the 'Runtime.disable' command.
--   Disables reporting of execution contexts creation.
runtimeDisable :: Handle -> IO ()
runtimeDisable handle = sendReceiveCommand handle PRuntimeDisable

instance Command PRuntimeDisable where
    type CommandResponse PRuntimeDisable = NoResponse
    commandName _ = "Runtime.disable"


-- | Parameters of the 'runtimeDiscardConsoleEntries' command.
data PRuntimeDiscardConsoleEntries = PRuntimeDiscardConsoleEntries
instance ToJSON PRuntimeDiscardConsoleEntries where toJSON _ = A.Null

-- | Function for the 'Runtime.discardConsoleEntries' command.
--   Discards collected exceptions and console API calls.
runtimeDiscardConsoleEntries :: Handle -> IO ()
runtimeDiscardConsoleEntries handle = sendReceiveCommand handle PRuntimeDiscardConsoleEntries

instance Command PRuntimeDiscardConsoleEntries where
    type CommandResponse PRuntimeDiscardConsoleEntries = NoResponse
    commandName _ = "Runtime.discardConsoleEntries"


-- | Parameters of the 'runtimeEnable' command.
data PRuntimeEnable = PRuntimeEnable
instance ToJSON PRuntimeEnable where toJSON _ = A.Null

-- | Function for the 'Runtime.enable' command.
--   Enables reporting of execution contexts creation by means of `executionContextCreated` event.
--   When the reporting gets enabled the event will be sent immediately for each existing execution
--   context.
runtimeEnable :: Handle -> IO ()
runtimeEnable handle = sendReceiveCommand handle PRuntimeEnable

instance Command PRuntimeEnable where
    type CommandResponse PRuntimeEnable = NoResponse
    commandName _ = "Runtime.enable"


-- | Parameters of the 'runtimeEvaluate' command.
data PRuntimeEvaluate = PRuntimeEvaluate {
  -- | Expression to evaluate.
  pRuntimeEvaluateExpression :: String,
  -- | Symbolic group name that can be used to release multiple objects.
  pRuntimeEvaluateObjectGroup :: Maybe String,
  -- | Determines whether Command Line API should be available during the evaluation.
  pRuntimeEvaluateIncludeCommandLineAPI :: Maybe Bool,
  -- | In silent mode exceptions thrown during evaluation are not reported and do not pause
  --   execution. Overrides `setPauseOnException` state.
  pRuntimeEvaluateSilent :: Maybe Bool,
  -- | Specifies in which execution context to perform evaluation. If the parameter is omitted the
  --   evaluation will be performed in the context of the inspected page.
  --   This is mutually exclusive with `uniqueContextId`, which offers an
  --   alternative way to identify the execution context that is more reliable
  --   in a multi-process environment.
  pRuntimeEvaluateContextId :: Maybe RuntimeExecutionContextId,
  -- | Whether the result is expected to be a JSON object that should be sent by value.
  pRuntimeEvaluateReturnByValue :: Maybe Bool,
  -- | Whether preview should be generated for the result.
  pRuntimeEvaluateGeneratePreview :: Maybe Bool,
  -- | Whether execution should be treated as initiated by user in the UI.
  pRuntimeEvaluateUserGesture :: Maybe Bool,
  -- | Whether execution should `await` for resulting value and return once awaited promise is
  --   resolved.
  pRuntimeEvaluateAwaitPromise :: Maybe Bool,
  -- | Whether to throw an exception if side effect cannot be ruled out during evaluation.
  --   This implies `disableBreaks` below.
  pRuntimeEvaluateThrowOnSideEffect :: Maybe Bool,
  -- | Terminate execution after timing out (number of milliseconds).
  pRuntimeEvaluateTimeout :: Maybe RuntimeTimeDelta,
  -- | Disable breakpoints during execution.
  pRuntimeEvaluateDisableBreaks :: Maybe Bool,
  -- | Setting this flag to true enables `let` re-declaration and top-level `await`.
  --   Note that `let` variables can only be re-declared if they originate from
  --   `replMode` themselves.
  pRuntimeEvaluateReplMode :: Maybe Bool,
  -- | The Content Security Policy (CSP) for the target might block 'unsafe-eval'
  --   which includes eval(), Function(), setTimeout() and setInterval()
  --   when called with non-callable arguments. This flag bypasses CSP for this
  --   evaluation and allows unsafe-eval. Defaults to true.
  pRuntimeEvaluateAllowUnsafeEvalBlockedByCSP :: Maybe Bool,
  -- | An alternative way to specify the execution context to evaluate in.
  --   Compared to contextId that may be reused across processes, this is guaranteed to be
  --   system-unique, so it can be used to prevent accidental evaluation of the expression
  --   in context different than intended (e.g. as a result of navigation across process
  --   boundaries).
  --   This is mutually exclusive with `contextId`.
  pRuntimeEvaluateUniqueContextId :: Maybe String,
  -- | Whether the result should be serialized according to https://w3c.github.io/webdriver-bidi.
  pRuntimeEvaluateGenerateWebDriverValue :: Maybe Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeEvaluate  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 , A.omitNothingFields = True}

instance FromJSON  PRuntimeEvaluate where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 }


-- | Function for the 'Runtime.evaluate' command.
--   Evaluates expression on global object.
--   Returns: 'PRuntimeEvaluate'
--   Returns: 'RuntimeEvaluate'
runtimeEvaluate :: Handle -> PRuntimeEvaluate -> IO RuntimeEvaluate
runtimeEvaluate handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeEvaluate' command.
data RuntimeEvaluate = RuntimeEvaluate {
  -- | Evaluation result.
  runtimeEvaluateResult :: RuntimeRemoteObject,
  -- | Exception details.
  runtimeEvaluateExceptionDetails :: Maybe RuntimeExceptionDetails
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeEvaluate where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 15 }

instance Command PRuntimeEvaluate where
    type CommandResponse PRuntimeEvaluate = RuntimeEvaluate
    commandName _ = "Runtime.evaluate"


-- | Parameters of the 'runtimeGetIsolateId' command.
data PRuntimeGetIsolateId = PRuntimeGetIsolateId
instance ToJSON PRuntimeGetIsolateId where toJSON _ = A.Null

-- | Function for the 'Runtime.getIsolateId' command.
--   Returns the isolate id.
--   Returns: 'RuntimeGetIsolateId'
runtimeGetIsolateId :: Handle -> IO RuntimeGetIsolateId
runtimeGetIsolateId handle = sendReceiveCommandResult handle PRuntimeGetIsolateId

-- | Return type of the 'runtimeGetIsolateId' command.
data RuntimeGetIsolateId = RuntimeGetIsolateId {
  -- | The isolate id.
  runtimeGetIsolateIdId :: String
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeGetIsolateId where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }

instance Command PRuntimeGetIsolateId where
    type CommandResponse PRuntimeGetIsolateId = RuntimeGetIsolateId
    commandName _ = "Runtime.getIsolateId"


-- | Parameters of the 'runtimeGetHeapUsage' command.
data PRuntimeGetHeapUsage = PRuntimeGetHeapUsage
instance ToJSON PRuntimeGetHeapUsage where toJSON _ = A.Null

-- | Function for the 'Runtime.getHeapUsage' command.
--   Returns the JavaScript heap usage.
--   It is the total usage of the corresponding isolate not scoped to a particular Runtime.
--   Returns: 'RuntimeGetHeapUsage'
runtimeGetHeapUsage :: Handle -> IO RuntimeGetHeapUsage
runtimeGetHeapUsage handle = sendReceiveCommandResult handle PRuntimeGetHeapUsage

-- | Return type of the 'runtimeGetHeapUsage' command.
data RuntimeGetHeapUsage = RuntimeGetHeapUsage {
  -- | Used heap size in bytes.
  runtimeGetHeapUsageUsedSize :: Double,
  -- | Allocated heap size in bytes.
  runtimeGetHeapUsageTotalSize :: Double
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeGetHeapUsage where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }

instance Command PRuntimeGetHeapUsage where
    type CommandResponse PRuntimeGetHeapUsage = RuntimeGetHeapUsage
    commandName _ = "Runtime.getHeapUsage"


-- | Parameters of the 'runtimeGetProperties' command.
data PRuntimeGetProperties = PRuntimeGetProperties {
  -- | Identifier of the object to return properties for.
  pRuntimeGetPropertiesObjectId :: RuntimeRemoteObjectId,
  -- | If true, returns properties belonging only to the element itself, not to its prototype
  --   chain.
  pRuntimeGetPropertiesOwnProperties :: Maybe Bool,
  -- | If true, returns accessor properties (with getter/setter) only; internal properties are not
  --   returned either.
  pRuntimeGetPropertiesAccessorPropertiesOnly :: Maybe Bool,
  -- | Whether preview should be generated for the results.
  pRuntimeGetPropertiesGeneratePreview :: Maybe Bool,
  -- | If true, returns non-indexed properties only.
  pRuntimeGetPropertiesNonIndexedPropertiesOnly :: Maybe Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeGetProperties  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 , A.omitNothingFields = True}

instance FromJSON  PRuntimeGetProperties where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 }


-- | Function for the 'Runtime.getProperties' command.
--   Returns properties of a given object. Object group of the result is inherited from the target
--   object.
--   Returns: 'PRuntimeGetProperties'
--   Returns: 'RuntimeGetProperties'
runtimeGetProperties :: Handle -> PRuntimeGetProperties -> IO RuntimeGetProperties
runtimeGetProperties handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeGetProperties' command.
data RuntimeGetProperties = RuntimeGetProperties {
  -- | Object properties.
  runtimeGetPropertiesResult :: [RuntimePropertyDescriptor],
  -- | Internal object properties (only of the element itself).
  runtimeGetPropertiesInternalProperties :: Maybe [RuntimeInternalPropertyDescriptor],
  -- | Object private properties.
  runtimeGetPropertiesPrivateProperties :: Maybe [RuntimePrivatePropertyDescriptor],
  -- | Exception details.
  runtimeGetPropertiesExceptionDetails :: Maybe RuntimeExceptionDetails
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeGetProperties where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 }

instance Command PRuntimeGetProperties where
    type CommandResponse PRuntimeGetProperties = RuntimeGetProperties
    commandName _ = "Runtime.getProperties"


-- | Parameters of the 'runtimeGlobalLexicalScopeNames' command.
data PRuntimeGlobalLexicalScopeNames = PRuntimeGlobalLexicalScopeNames {
  -- | Specifies in which execution context to lookup global scope variables.
  pRuntimeGlobalLexicalScopeNamesExecutionContextId :: Maybe RuntimeExecutionContextId
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeGlobalLexicalScopeNames  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 , A.omitNothingFields = True}

instance FromJSON  PRuntimeGlobalLexicalScopeNames where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 31 }


-- | Function for the 'Runtime.globalLexicalScopeNames' command.
--   Returns all let, const and class variables from global scope.
--   Returns: 'PRuntimeGlobalLexicalScopeNames'
--   Returns: 'RuntimeGlobalLexicalScopeNames'
runtimeGlobalLexicalScopeNames :: Handle -> PRuntimeGlobalLexicalScopeNames -> IO RuntimeGlobalLexicalScopeNames
runtimeGlobalLexicalScopeNames handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeGlobalLexicalScopeNames' command.
data RuntimeGlobalLexicalScopeNames = RuntimeGlobalLexicalScopeNames {
  runtimeGlobalLexicalScopeNamesNames :: [String]
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeGlobalLexicalScopeNames where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }

instance Command PRuntimeGlobalLexicalScopeNames where
    type CommandResponse PRuntimeGlobalLexicalScopeNames = RuntimeGlobalLexicalScopeNames
    commandName _ = "Runtime.globalLexicalScopeNames"


-- | Parameters of the 'runtimeQueryObjects' command.
data PRuntimeQueryObjects = PRuntimeQueryObjects {
  -- | Identifier of the prototype to return objects for.
  pRuntimeQueryObjectsPrototypeObjectId :: RuntimeRemoteObjectId,
  -- | Symbolic group name that can be used to release the results.
  pRuntimeQueryObjectsObjectGroup :: Maybe String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeQueryObjects  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 , A.omitNothingFields = True}

instance FromJSON  PRuntimeQueryObjects where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 20 }


-- | Function for the 'Runtime.queryObjects' command.
--   
--   Returns: 'PRuntimeQueryObjects'
--   Returns: 'RuntimeQueryObjects'
runtimeQueryObjects :: Handle -> PRuntimeQueryObjects -> IO RuntimeQueryObjects
runtimeQueryObjects handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeQueryObjects' command.
data RuntimeQueryObjects = RuntimeQueryObjects {
  -- | Array with objects.
  runtimeQueryObjectsObjects :: RuntimeRemoteObject
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeQueryObjects where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 19 }

instance Command PRuntimeQueryObjects where
    type CommandResponse PRuntimeQueryObjects = RuntimeQueryObjects
    commandName _ = "Runtime.queryObjects"


-- | Parameters of the 'runtimeReleaseObject' command.
data PRuntimeReleaseObject = PRuntimeReleaseObject {
  -- | Identifier of the object to release.
  pRuntimeReleaseObjectObjectId :: RuntimeRemoteObjectId
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeReleaseObject  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 , A.omitNothingFields = True}

instance FromJSON  PRuntimeReleaseObject where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 }


-- | Function for the 'Runtime.releaseObject' command.
--   Releases remote object with given id.
--   Returns: 'PRuntimeReleaseObject'
runtimeReleaseObject :: Handle -> PRuntimeReleaseObject -> IO ()
runtimeReleaseObject handle params = sendReceiveCommand handle params

instance Command PRuntimeReleaseObject where
    type CommandResponse PRuntimeReleaseObject = NoResponse
    commandName _ = "Runtime.releaseObject"


-- | Parameters of the 'runtimeReleaseObjectGroup' command.
data PRuntimeReleaseObjectGroup = PRuntimeReleaseObjectGroup {
  -- | Symbolic object group name.
  pRuntimeReleaseObjectGroupObjectGroup :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeReleaseObjectGroup  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 26 , A.omitNothingFields = True}

instance FromJSON  PRuntimeReleaseObjectGroup where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 26 }


-- | Function for the 'Runtime.releaseObjectGroup' command.
--   Releases all remote objects that belong to a given group.
--   Returns: 'PRuntimeReleaseObjectGroup'
runtimeReleaseObjectGroup :: Handle -> PRuntimeReleaseObjectGroup -> IO ()
runtimeReleaseObjectGroup handle params = sendReceiveCommand handle params

instance Command PRuntimeReleaseObjectGroup where
    type CommandResponse PRuntimeReleaseObjectGroup = NoResponse
    commandName _ = "Runtime.releaseObjectGroup"


-- | Parameters of the 'runtimeRunIfWaitingForDebugger' command.
data PRuntimeRunIfWaitingForDebugger = PRuntimeRunIfWaitingForDebugger
instance ToJSON PRuntimeRunIfWaitingForDebugger where toJSON _ = A.Null

-- | Function for the 'Runtime.runIfWaitingForDebugger' command.
--   Tells inspected instance to run if it was waiting for debugger to attach.
runtimeRunIfWaitingForDebugger :: Handle -> IO ()
runtimeRunIfWaitingForDebugger handle = sendReceiveCommand handle PRuntimeRunIfWaitingForDebugger

instance Command PRuntimeRunIfWaitingForDebugger where
    type CommandResponse PRuntimeRunIfWaitingForDebugger = NoResponse
    commandName _ = "Runtime.runIfWaitingForDebugger"


-- | Parameters of the 'runtimeRunScript' command.
data PRuntimeRunScript = PRuntimeRunScript {
  -- | Id of the script to run.
  pRuntimeRunScriptScriptId :: RuntimeScriptId,
  -- | Specifies in which execution context to perform script run. If the parameter is omitted the
  --   evaluation will be performed in the context of the inspected page.
  pRuntimeRunScriptExecutionContextId :: Maybe RuntimeExecutionContextId,
  -- | Symbolic group name that can be used to release multiple objects.
  pRuntimeRunScriptObjectGroup :: Maybe String,
  -- | In silent mode exceptions thrown during evaluation are not reported and do not pause
  --   execution. Overrides `setPauseOnException` state.
  pRuntimeRunScriptSilent :: Maybe Bool,
  -- | Determines whether Command Line API should be available during the evaluation.
  pRuntimeRunScriptIncludeCommandLineAPI :: Maybe Bool,
  -- | Whether the result is expected to be a JSON object which should be sent by value.
  pRuntimeRunScriptReturnByValue :: Maybe Bool,
  -- | Whether preview should be generated for the result.
  pRuntimeRunScriptGeneratePreview :: Maybe Bool,
  -- | Whether execution should `await` for resulting value and return once awaited promise is
  --   resolved.
  pRuntimeRunScriptAwaitPromise :: Maybe Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeRunScript  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 , A.omitNothingFields = True}

instance FromJSON  PRuntimeRunScript where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 17 }


-- | Function for the 'Runtime.runScript' command.
--   Runs script with given id in a given context.
--   Returns: 'PRuntimeRunScript'
--   Returns: 'RuntimeRunScript'
runtimeRunScript :: Handle -> PRuntimeRunScript -> IO RuntimeRunScript
runtimeRunScript handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeRunScript' command.
data RuntimeRunScript = RuntimeRunScript {
  -- | Run result.
  runtimeRunScriptResult :: RuntimeRemoteObject,
  -- | Exception details.
  runtimeRunScriptExceptionDetails :: Maybe RuntimeExceptionDetails
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeRunScript where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 16 }

instance Command PRuntimeRunScript where
    type CommandResponse PRuntimeRunScript = RuntimeRunScript
    commandName _ = "Runtime.runScript"


-- | Parameters of the 'runtimeSetAsyncCallStackDepth' command.
data PRuntimeSetAsyncCallStackDepth = PRuntimeSetAsyncCallStackDepth {
  -- | Maximum depth of async call stacks. Setting to `0` will effectively disable collecting async
  --   call stacks (default).
  pRuntimeSetAsyncCallStackDepthMaxDepth :: Int
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeSetAsyncCallStackDepth  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 , A.omitNothingFields = True}

instance FromJSON  PRuntimeSetAsyncCallStackDepth where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 30 }


-- | Function for the 'Runtime.setAsyncCallStackDepth' command.
--   Enables or disables async call stacks tracking.
--   Returns: 'PRuntimeSetAsyncCallStackDepth'
runtimeSetAsyncCallStackDepth :: Handle -> PRuntimeSetAsyncCallStackDepth -> IO ()
runtimeSetAsyncCallStackDepth handle params = sendReceiveCommand handle params

instance Command PRuntimeSetAsyncCallStackDepth where
    type CommandResponse PRuntimeSetAsyncCallStackDepth = NoResponse
    commandName _ = "Runtime.setAsyncCallStackDepth"


-- | Parameters of the 'runtimeSetCustomObjectFormatterEnabled' command.
data PRuntimeSetCustomObjectFormatterEnabled = PRuntimeSetCustomObjectFormatterEnabled {
  pRuntimeSetCustomObjectFormatterEnabledEnabled :: Bool
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeSetCustomObjectFormatterEnabled  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 39 , A.omitNothingFields = True}

instance FromJSON  PRuntimeSetCustomObjectFormatterEnabled where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 39 }


-- | Function for the 'Runtime.setCustomObjectFormatterEnabled' command.
--   
--   Returns: 'PRuntimeSetCustomObjectFormatterEnabled'
runtimeSetCustomObjectFormatterEnabled :: Handle -> PRuntimeSetCustomObjectFormatterEnabled -> IO ()
runtimeSetCustomObjectFormatterEnabled handle params = sendReceiveCommand handle params

instance Command PRuntimeSetCustomObjectFormatterEnabled where
    type CommandResponse PRuntimeSetCustomObjectFormatterEnabled = NoResponse
    commandName _ = "Runtime.setCustomObjectFormatterEnabled"


-- | Parameters of the 'runtimeSetMaxCallStackSizeToCapture' command.
data PRuntimeSetMaxCallStackSizeToCapture = PRuntimeSetMaxCallStackSizeToCapture {
  pRuntimeSetMaxCallStackSizeToCaptureSize :: Int
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeSetMaxCallStackSizeToCapture  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 36 , A.omitNothingFields = True}

instance FromJSON  PRuntimeSetMaxCallStackSizeToCapture where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 36 }


-- | Function for the 'Runtime.setMaxCallStackSizeToCapture' command.
--   
--   Returns: 'PRuntimeSetMaxCallStackSizeToCapture'
runtimeSetMaxCallStackSizeToCapture :: Handle -> PRuntimeSetMaxCallStackSizeToCapture -> IO ()
runtimeSetMaxCallStackSizeToCapture handle params = sendReceiveCommand handle params

instance Command PRuntimeSetMaxCallStackSizeToCapture where
    type CommandResponse PRuntimeSetMaxCallStackSizeToCapture = NoResponse
    commandName _ = "Runtime.setMaxCallStackSizeToCapture"


-- | Parameters of the 'runtimeTerminateExecution' command.
data PRuntimeTerminateExecution = PRuntimeTerminateExecution
instance ToJSON PRuntimeTerminateExecution where toJSON _ = A.Null

-- | Function for the 'Runtime.terminateExecution' command.
--   Terminate current or next JavaScript execution.
--   Will cancel the termination when the outer-most script execution ends.
runtimeTerminateExecution :: Handle -> IO ()
runtimeTerminateExecution handle = sendReceiveCommand handle PRuntimeTerminateExecution

instance Command PRuntimeTerminateExecution where
    type CommandResponse PRuntimeTerminateExecution = NoResponse
    commandName _ = "Runtime.terminateExecution"


-- | Parameters of the 'runtimeAddBinding' command.
data PRuntimeAddBinding = PRuntimeAddBinding {
  pRuntimeAddBindingName :: String,
  -- | If specified, the binding is exposed to the executionContext with
  --   matching name, even for contexts created after the binding is added.
  --   See also `ExecutionContext.name` and `worldName` parameter to
  --   `Page.addScriptToEvaluateOnNewDocument`.
  --   This parameter is mutually exclusive with `executionContextId`.
  pRuntimeAddBindingExecutionContextName :: Maybe String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeAddBinding  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 18 , A.omitNothingFields = True}

instance FromJSON  PRuntimeAddBinding where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 18 }


-- | Function for the 'Runtime.addBinding' command.
--   If executionContextId is empty, adds binding with the given name on the
--   global objects of all inspected contexts, including those created later,
--   bindings survive reloads.
--   Binding function takes exactly one argument, this argument should be string,
--   in case of any other input, function throws an exception.
--   Each binding function call produces Runtime.bindingCalled notification.
--   Returns: 'PRuntimeAddBinding'
runtimeAddBinding :: Handle -> PRuntimeAddBinding -> IO ()
runtimeAddBinding handle params = sendReceiveCommand handle params

instance Command PRuntimeAddBinding where
    type CommandResponse PRuntimeAddBinding = NoResponse
    commandName _ = "Runtime.addBinding"


-- | Parameters of the 'runtimeRemoveBinding' command.
data PRuntimeRemoveBinding = PRuntimeRemoveBinding {
  pRuntimeRemoveBindingName :: String
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeRemoveBinding  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 , A.omitNothingFields = True}

instance FromJSON  PRuntimeRemoveBinding where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 21 }


-- | Function for the 'Runtime.removeBinding' command.
--   This method does not remove binding function from global object but
--   unsubscribes current runtime agent from Runtime.bindingCalled notifications.
--   Returns: 'PRuntimeRemoveBinding'
runtimeRemoveBinding :: Handle -> PRuntimeRemoveBinding -> IO ()
runtimeRemoveBinding handle params = sendReceiveCommand handle params

instance Command PRuntimeRemoveBinding where
    type CommandResponse PRuntimeRemoveBinding = NoResponse
    commandName _ = "Runtime.removeBinding"


-- | Parameters of the 'runtimeGetExceptionDetails' command.
data PRuntimeGetExceptionDetails = PRuntimeGetExceptionDetails {
  -- | The error object for which to resolve the exception details.
  pRuntimeGetExceptionDetailsErrorObjectId :: RuntimeRemoteObjectId
} deriving (Generic, Eq, Show, Read)
instance ToJSON PRuntimeGetExceptionDetails  where
   toJSON = A.genericToJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 27 , A.omitNothingFields = True}

instance FromJSON  PRuntimeGetExceptionDetails where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 27 }


-- | Function for the 'Runtime.getExceptionDetails' command.
--   This method tries to lookup and populate exception details for a
--   JavaScript Error object.
--   Note that the stackTrace portion of the resulting exceptionDetails will
--   only be populated if the Runtime domain was enabled at the time when the
--   Error was thrown.
--   Returns: 'PRuntimeGetExceptionDetails'
--   Returns: 'RuntimeGetExceptionDetails'
runtimeGetExceptionDetails :: Handle -> PRuntimeGetExceptionDetails -> IO RuntimeGetExceptionDetails
runtimeGetExceptionDetails handle params = sendReceiveCommandResult handle params

-- | Return type of the 'runtimeGetExceptionDetails' command.
data RuntimeGetExceptionDetails = RuntimeGetExceptionDetails {
  runtimeGetExceptionDetailsExceptionDetails :: Maybe RuntimeExceptionDetails
} deriving (Generic, Eq, Show, Read)

instance FromJSON  RuntimeGetExceptionDetails where
   parseJSON = A.genericParseJSON A.defaultOptions{A.fieldLabelModifier = uncapitalizeFirst . drop 26 }

instance Command PRuntimeGetExceptionDetails where
    type CommandResponse PRuntimeGetExceptionDetails = RuntimeGetExceptionDetails
    commandName _ = "Runtime.getExceptionDetails"



