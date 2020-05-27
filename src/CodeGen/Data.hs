{-# LANGUAGE OverloadedStrings #-}
module CodeGen.Data
  ( createData
  , createBootData
  , createFieldData
  )
where

import           RIO
import qualified RIO.List                      as L
import qualified RIO.Map                       as Map
import qualified RIO.Set                       as Set
import qualified RIO.Text                      as T
import           RIO.Writer                     ( runWriterT
                                                , tell
                                                )
import qualified Discovery.RestDescription.Schema
                                               as Desc
import qualified JSON.Schema                   as JSON
import           CodeGen.Types
import           CodeGen.Util

createData :: ModuleName -> Desc.Schema -> GenData Text
createData moduleName schema = do
  name <- lift $ get Desc.schemaId "schema id" schema
  let desc = Desc.schemaDescription schema
  schemaType <- get Desc.schemaType "schema type" schema
  case schemaType of
    (Desc.ObjectType obj  ) -> createObject moduleName name desc obj
    (Desc.ArrayType  array) -> createArray moduleName name array schema
    Desc.AnyType            -> createAnyRecord name desc
    _                       -> undefined
createObject
  :: ModuleName -> RecordName -> Maybe Desc -> Desc.Object -> GenData Text
createObject moduleName name desc obj = do
  tell [GenImport ImportPrelude]
  props    <- createObjectProperties moduleName name desc obj
  addProps <- createObjectAdditionalProperties moduleName name desc obj
  maybe (error "faild to get JSON object properties nor additionalProperties")
        pure
        (props <|> addProps)

createObjectProperties
  :: ModuleName
  -> RecordName
  -> Maybe Desc
  -> Desc.Object
  -> GenData (Maybe Text)
createObjectProperties moduleName name desc obj =
  case Desc.objectProperties obj of
    (Just props) -> createObjectPropertiesContent moduleName name desc props
    _            -> pure Nothing

createObjectPropertiesContent
  :: ModuleName
  -> RecordName
  -> Maybe Desc
  -> Desc.ObjectProperties
  -> GenData (Maybe Text)
createObjectPropertiesContent moduleName name desc props = if Map.null props
  then do
    let field =
          "    " <> T.concat ["un", name] <> " :: Map RIO.Text Aeson.Value"
        record =
          createRecordContent name field 1 desc
            <> " deriving (Aeson.ToJSON, Aeson.FromJSON)"
    pure . pure $ record
  else do
    field <- createField moduleName name props
    let record = createRecordContent name field (Map.size props) desc
        aeson  = createAesonContent moduleName name props
    pure . pure $ record <> "\n\n" <> aeson

createObjectAdditionalProperties
  :: ModuleName
  -> RecordName
  -> Maybe Desc
  -> Desc.Object
  -> GenData (Maybe Text)
createObjectAdditionalProperties moduleName name desc obj =
  case Desc.objectAdditionalProperties obj of
    (Just (JSON.AdditionalPropertiesSchema schema)) ->
      createObjectAdditionalPropertiesContent moduleName name desc schema
    (Just (JSON.AdditionalPropertiesBool _)) -> undefined
    Nothing -> createObjectAdditionalPropertiesContent
      moduleName
      name
      desc
      JSON.Schema
        { JSON.schemaType             = Just JSON.AnyType
        , JSON.schemaTitle            = Nothing
        , JSON.schemaDescription      = Nothing
        , JSON.schemaExamples         = Nothing
        , JSON.schemaComment          = Nothing
        , JSON.schemaEnum             = Nothing
        , JSON.schemaEnumDescriptions = Nothing
        , JSON.schemaConst            = Nothing
        }

createObjectAdditionalPropertiesContent
  :: ModuleName
  -> RecordName
  -> Maybe Desc
  -> JSON.Schema
  -> GenData (Maybe Text)
createObjectAdditionalPropertiesContent moduleName name desc schema = do
  fieldType <- createType moduleName (name <> "Value") schema True
  let fieldDesc = descContent 4 (JSON.schemaDescription schema)
      field =
        "    " <> T.concat ["un", name] <> " :: Map RIO.Text " <> fieldType
      record =
        createRecordContent name (fieldDesc <> field) 1 desc
          <> " deriving (Aeson.ToJSON, Aeson.FromJSON)"
  pure . pure $ record

createArray
  :: ModuleName -> RecordName -> Desc.Array -> Desc.Schema -> GenData Text
createArray moduleName name array schema = do
  tell [GenImport ImportPrelude]
  createArrayRecord moduleName name schema array

createArrayRecord
  :: ModuleName -> SchemaName -> Desc.Schema -> Desc.Array -> GenData Text
createArrayRecord moduleName name schema array = case Desc.arrayItems array of
  (Just (JSON.ArrayItemsItem fieldSchema)) -> do
    let desc      = Desc.schemaDescription schema
        enumDescs = Desc.schemaEnumDescriptions schema
        arrayName = name <> "Item"
    fieldType <- createType
      moduleName
      arrayName
      (fieldSchema { JSON.schemaDescription      = desc
                   , JSON.schemaEnumDescriptions = enumDescs
                   }
      )
      True
    pure $ "type " <> name <> " = " <> "[" <> fieldType <> "]"
  _ -> undefined

createAnyRecord :: RecordName -> Maybe Desc -> GenData Text
createAnyRecord name desc =
  pure
    $  maybe
         ""
         (\s -> "{-|\n" <> (T.unlines . fmap ("  " <>) . T.lines $ s) <> "-}\n")
         desc
    <> "type "
    <> name
    <> " = Aeson.Value"

createBootData :: Desc.Schema -> IO Text
createBootData schema = do
  schemaType <- get Desc.schemaType "schema type" schema
  name       <- get Desc.schemaId "schema id" schema
  pure $ case schemaType of
    (Desc.ObjectType _) ->
      "data "
        <> name
        <> "\n"
        <> "instance FromJSON "
        <> name
        <> "\n"
        <> "instance ToJSON "
        <> name
        <> "\n"
    (Desc.ArrayType _) ->
      "type " <> name <> " = " <> "[" <> name <> "Item" <> "]"
    Desc.AnyType -> "type " <> name <> " = Aeson.Value"
    _            -> undefined

createField :: ModuleName -> RecordName -> Desc.ObjectProperties -> GenData Text
createField moduleName name props = do
  fields <- Map.foldrWithKey cons (pure mempty) props
  pure $ T.intercalate ",\n\n" fields
 where
  cons s schema acc = do
    let camelName = name <> toCamelName s
        fieldName = unTitle camelName
        desc      = descContent 4 $ JSON.schemaDescription schema
    fieldType <- createType moduleName camelName schema False
    let field = "    " <> fieldName <> " :: " <> fieldType
    ((desc <> field) :) <$> acc

descContent :: Int -> Maybe Text -> Text
descContent n = maybe
  ""
  (\s ->
    indent
      <> "{-|\n"
      <> (T.unlines . fmap ((indent <> "  ") <>) . T.lines $ s)
      <> indent
      <> "-}\n"
  )
  where indent = T.concat $ take n $ L.repeat " "

createType
  :: ModuleName -> SchemaName -> JSON.Schema -> Required -> GenData Text
createType moduleName name schema required = do
  jsonType <- get JSON.schemaType "schemaType" schema
  _type    <- case jsonType of
    (JSON.StringType  _) -> createEnumType "RIO.Text" name schema
    (JSON.IntegerType _) -> pure "RIO.Int"
    (JSON.NumberType  _) -> pure "RIO.Float"
    (JSON.ObjectType _) ->
      tell [GenSchema (name, schema)] >> pure (moduleName <> "." <> name)
    (JSON.RefType ref) ->
      if Just ref /= L.headMaybe (reverse (T.split (== '.') moduleName)) -- TODO: ここで RecordName が欲しい
        then tell [GenImport (Import ref)] >> pure (ref <> "." <> ref)
        else pure ref
    (JSON.ArrayType array) -> createArrayType moduleName name schema array
    JSON.BooleanType       -> pure "RIO.Bool"
    JSON.AnyType           -> pure "Aeson.Value"
    JSON.NullType          -> undefined
  if required then pure _type else pure $ "Maybe " <> _type

createEnumType :: Text -> SchemaName -> JSON.Schema -> GenData Text
createEnumType defaultType name schema = case JSON.schemaEnum schema of
  (Just jsonEnum) -> do
    let descs = fromMaybe (L.repeat "") $ JSON.schemaEnumDescriptions schema
    tell [GenEnum (name, zip jsonEnum descs), GenImport ImportGenerics]
    tell [GenImport ImportEnum]
    pure name
  _ -> pure defaultType

createArrayType
  :: ModuleName -> SchemaName -> JSON.Schema -> JSON.Array -> GenData Text
createArrayType moduleName name schema array = case JSON.arrayItems array of
  (Just (JSON.ArrayItemsItem fieldSchema)) -> do
    let desc           = JSON.schemaDescription schema
        enumDescs      = JSON.schemaEnumDescriptions schema
        newFieldSchema = if isJust enumDescs
          then fieldSchema { JSON.schemaDescription      = desc
                           , JSON.schemaEnumDescriptions = enumDescs
                           }
          else fieldSchema { JSON.schemaDescription = desc }
    fieldType <- createType moduleName name newFieldSchema True
    pure $ "[" <> fieldType <> "]"
  _ -> undefined

createRecordContent :: RecordName -> Text -> Int -> Maybe Text -> Text
createRecordContent name field size desc
  = maybe
      ""
      (\s -> "{-|\n" <> (T.unlines . fmap ("  " <>) . T.lines $ s) <> "-}\n")
      desc
    <> (if size == 1 then "newtype " else "data ")
    <> name
    <> " = "
    <> name
    <> (if size == 0 then "" else "\n  {\n" <> field <> "\n  }")

createAesonContent :: ModuleName -> RecordName -> Desc.ObjectProperties -> Text
createAesonContent moduleName name props =
  createFromJSONContent moduleName name props
    <> "\n\n"
    <> createToJSONContent moduleName name props

createFromJSONContent
  :: ModuleName -> RecordName -> Desc.ObjectProperties -> Text
createFromJSONContent moduleName name props
  | Map.size props == 0
  = "instance Aeson.FromJSON "
    <> moduleName
    <> "."
    <> name
    <> " where\n  parseJSON = Aeson.withObject \""
    <> name
    <> "\" (\\v -> if null v then pure "
    <> moduleName
    <> "."
    <> name
    <> " else mempty)"
  | otherwise
  = "instance Aeson.FromJSON "
    <> moduleName
    <> "."
    <> name
    <> " where\n  parseJSON = Aeson.withObject \""
    <> name
    <> "\" $ \\v -> "
    <> moduleName
    <> "."
    <> name
    <> "\n    <$> "
    <> T.intercalate "\n    <*> " (Map.foldrWithKey cons mempty props)
  where cons s _schema acc = ("v Aeson..:?" <> " \"" <> s <> "\"") : acc

createToJSONContent :: ModuleName -> RecordName -> Desc.ObjectProperties -> Text
createToJSONContent moduleName name props
  | Map.size props == 0
  = "instance Aeson.ToJSON "
    <> moduleName
    <> "."
    <> name
    <> " where\n"
    <> "  toJSON "
    <> moduleName
    <> "."
    <> name
    <> " = Aeson.object mempty"
  | otherwise
  = "instance Aeson.ToJSON "
    <> moduleName
    <> "."
    <> name
    <> " where\n  toJSON(\n    "
    <> moduleName
    <> "."
    <> name
    <> "\n      "
    <> args
    <> "\n    ) = Aeson.object\n    [ "
    <> obj
    <> "\n    ]"
 where
  names =
    (\key -> (key, unTitle name <> toCamelName key <> "'")) <$> Map.keys props
  args = T.intercalate "\n      " (snd <$> names)
  obj  = T.intercalate
    "\n    , "
    ((\(key, argName) -> "\"" <> key <> "\" Aeson..= " <> argName) <$> names)

createFieldData :: ModuleName -> [Gen] -> GenImport Text
createFieldData moduleName = fmap unLines . foldr f (pure mempty)
 where
  f :: Gen -> GenImport [Text] -> GenImport [Text]
  f (GenSchema schema) acc = do
    (a, schemas) <- lift $ runWriterT $ createFieldDatum moduleName schema
    if null schemas
      then (a :) <$> acc
      else do
        b <- createFieldData moduleName schemas
        (a :) <$> ((b :) <$> acc)
  f (GenEnum (name, enums)) acc = do
    let a     = createFieldEnumContent name enums
        aeson = createFieldEnumAesonContent moduleName name enums
    ((a <> "\n\n" <> aeson) :) <$> acc
  f (GenImport ref) acc = do
    tell $ Set.singleton ref
    acc

createFieldEnumContent :: SchemaName -> EnumList -> Text
createFieldEnumContent name enums =
  "data "
    <> name
    <> "\n  =\n"
    <> T.intercalate
         "\n  |\n"
         (fmap
           (\(e, d) -> descContent 2 (Just d) <> "  " <> name <> toCamelName
             (T.toLower e)
           )
           enums
         )
    <> "\n  deriving (Show, Generic)"

createFieldEnumAesonContent :: ModuleName -> SchemaName -> EnumList -> Text
createFieldEnumAesonContent moduleName name enums =
  createFieldEnumConstructorTagModifier name
    <> "\n"
    <> createFieldEnumConstructorTagModifierValues name enums
    <> "\n"
    <> createFieldEnumFromJSONContent moduleName name
    <> "\n"
    <> createFieldEnumToJSONContent moduleName name

createFieldEnumConstructorTagModifier :: SchemaName -> Text
createFieldEnumConstructorTagModifier name = T.intercalate
  "\n"
  [ fn <> " :: String -> String"
  , fn <> " s = fromMaybe s $ Map.lookup s " <> fn <> "Map"
  , ""
  ]
  where fn = "to" <> name

createFieldEnumConstructorTagModifierValues :: SchemaName -> EnumList -> Text
createFieldEnumConstructorTagModifierValues name enums = T.intercalate
  "\n"
  [ fn <> " :: Map String String"
  , fn
  <> " =\n  Map.fromList\n    ["
  <> T.intercalate
       "\n    ,"
       (fmap
         (\(e, _) ->
           " (\""
             <> name
             <> toCamelName (T.toLower e)
             <> "\""
             <> ", "
             <> "\""
             <> e
             <> "\")"
         )
         enums
       )
  <> "\n    ]"
  , ""
  ]
  where fn = "to" <> name <> "Map"

createFieldEnumFromJSONContent :: ModuleName -> SchemaName -> Text
createFieldEnumFromJSONContent moduleName name =
  "instance Aeson.FromJSON "
    <> moduleName
    <> "."
    <> name
    <> " where\n"
    <> "  parseJSON = Aeson.genericParseJSON Aeson.defaultOptions { Aeson.constructorTagModifier = to"
    <> name
    <> " }\n"

createFieldEnumToJSONContent :: ModuleName -> SchemaName -> Text
createFieldEnumToJSONContent moduleName name =
  "instance Aeson.ToJSON "
    <> moduleName
    <> "."
    <> name
    <> " where\n"
    <> "  toJSON = Aeson.genericToJSON Aeson.defaultOptions { Aeson.constructorTagModifier = to"
    <> name
    <> " }\n"

createFieldDatum :: ModuleName -> Schema -> GenData Text
createFieldDatum moduleName (name, schema) = case JSON.schemaType schema of
  (Just (JSON.ObjectType obj)) -> do
    let desc = JSON.schemaDescription schema
    fields <- createFieldDatumFields moduleName name desc obj
    field  <- createFieldDatumField moduleName name desc obj
    maybe
      (error "faild to get JSON object properties nor additionalProperties")
      pure
      (fields <|> field)
  (Just _) -> undefined
  Nothing  -> undefined

createFieldDatumFields
  :: ModuleName
  -> SchemaName
  -> Maybe Desc
  -> JSON.Object
  -> GenData (Maybe Text)
createFieldDatumFields moduleName name desc obj =
  case JSON.objectProperties obj of
    (Just props) -> createObjectPropertiesContent moduleName name desc props
    Nothing      -> pure Nothing

createFieldDatumField
  :: ModuleName
  -> SchemaName
  -> Maybe Desc
  -> JSON.Object
  -> GenData (Maybe Text)
createFieldDatumField moduleName name desc obj =
  case JSON.objectAdditionalProperties obj of
    (Just (JSON.AdditionalPropertiesSchema schema)) ->
      createObjectAdditionalPropertiesContent moduleName name desc schema
    (Just (JSON.AdditionalPropertiesBool _)) -> undefined
    Nothing -> pure Nothing