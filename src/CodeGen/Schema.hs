{-# LANGUAGE OverloadedStrings #-}
module CodeGen.Schema where

import           Prelude                        ( print )
import qualified RIO.Directory                 as Dir

import           RIO
import qualified RIO.ByteString                as B
import qualified RIO.FilePath                  as FP
import qualified RIO.List                      as L
import qualified RIO.Map                       as Map
import qualified RIO.Set                       as Set
import qualified RIO.Text                      as T
import           RIO.Writer                     ( runWriterT )
import           Discovery.RestDescription
import           Discovery.RestDescription.Schema
import           CodeGen.Schema.Record         as Record
import           CodeGen.Types           hiding ( Schema )
import           CodeGen.Util

schemaName :: Text
schemaName = "Schema"

schemaDir :: SchemaDir
schemaDir = T.unpack schemaName

defaultExtentions :: [Text]
defaultExtentions =
  [ "{-# LANGUAGE DeriveGeneric #-}"
  , "{-# LANGUAGE GeneralizedNewtypeDeriving #-}"
  , "{-# LANGUAGE OverloadedStrings #-}"
  ]

defaultImports :: [Text]
defaultImports = ["import qualified Data.Aeson as Aeson"]

gen :: ServiceName -> ServiceVersion -> RestDescriptionSchemas -> IO ()
gen svcName svcVer schemas = withDir schemaDir $ do
  dir <- Dir.getCurrentDirectory
  print dir

  foldM_ (createFile svcName svcVer) Map.empty schemas

type RefRecords = Map RecordName (Set RecordName)

createFile
  :: ServiceName -> ServiceVersion -> RefRecords -> Schema -> IO RefRecords
createFile svcName svcVer refRecs schema = do
  name <- get schemaId "schemaId" schema

  let moduleName = T.intercalate "." [svcName, svcVer, schemaName, name]
  print moduleName

  refs <- createHsFile svcName svcVer name moduleName refRecs schema
  createHsBootFile name moduleName schema
  pure refs

createHsFile
  :: ServiceName
  -> ServiceVersion
  -> RecordName
  -> ModuleName
  -> RefRecords
  -> Schema
  -> IO RefRecords
createHsFile svcName svcVer name moduleName refRecs schema = do
  (record, jsonObjs) <- runWriterT $ Record.createRecord moduleName schema
  (records, refs) <- runWriterT $ Record.createFieldRecords moduleName jsonObjs
  let path = FP.addExtension (T.unpack name) "hs"
      imports =
        L.sort
          $  defaultImports
          <> createImports svcName svcVer name refRecs refs
      content =
        flip T.snoc '\n'
          . unLines
          $ [ T.intercalate "\n" defaultExtentions
            , "module " <> moduleName <> " where"
            , T.intercalate "\n" imports
            , record
            , records
            ]
  B.writeFile path (T.encodeUtf8 content)

  let names = Set.map unRef . Set.filter filterRecord $ refs
  pure $ if Set.null names
    then refRecs
    else do
      let refRec = Map.singleton name names
      Map.union refRec refRecs
 where
  unRef :: Ref -> Text
  unRef (Ref ref) = ref
  unRef _         = undefined
  filterRecord :: Ref -> Bool
  filterRecord (Ref _) = True
  filterRecord _       = False

createHsBootFile :: RecordName -> ModuleName -> Schema -> IO ()
createHsBootFile name moduleName schema = do
  record <- Record.createBootRecord schema

  let path = FP.addExtension (T.unpack name) "hs-boot"
      content =
        flip T.snoc '\n'
          . unLines
          $ ["module " <> moduleName <> " where", "import Data.Aeson", record]
  B.writeFile path (T.encodeUtf8 content)

createImports
  :: ServiceName
  -> ServiceVersion
  -> RecordName
  -> RefRecords
  -> Set Ref
  -> [Text]
createImports svcName svcVersion name refRecs = fmap f . Set.toList
 where
  f RefPrelude = "import RIO"
  f (Ref ref) =
    let t = isCyclicImport name ref Set.empty refRecs
        s = if t then "{-# SOURCE #-} " else ""
    in  "import "
        <> s
        <> "qualified "
        <> svcName
        <> "."
        <> svcVersion
        <> "."
        <> schemaName
        <> "."
        <> ref
        <> " as "
        <> ref
  f RefEnum     = "import qualified RIO.Map as Map"
  f RefGenerics = "import GHC.Generics()"

isCyclicImport
  :: RecordName -> RecordName -> Set RecordName -> RefRecords -> Bool
isCyclicImport name ref acc refRecs
  | Set.member ref acc
  = False
  | otherwise
  = maybe
      False
      (\rs -> Set.member name rs || any
        (== True)
        (fmap (\r -> isCyclicImport name r (Set.insert ref acc) refRecs)
              (Set.toList rs)
        )
      )
    $ Map.lookup ref refRecs
