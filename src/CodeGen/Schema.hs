{-# LANGUAGE OverloadedStrings #-}
module CodeGen.Schema
  ( gen
  )
where

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
import           CodeGen.Data                  as Data
import qualified CodeGen.ImportInfo            as ImportInfo
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
  foldM_ (createFile svcName svcVer) ImportInfo.empty schemas

createFile
  :: ServiceName -> ServiceVersion -> ImportInfo -> Schema -> IO ImportInfo
createFile svcName svcVer importInfo schema = do
  name <- get schemaId "schemaId" schema
  let
    t     = ImportInfo.member name importInfo
    cname = if t then name <> "'" else name
    imprtInfo =
      if t then ImportInfo.rename name cname importInfo else importInfo
    moduleName = T.intercalate "." [svcName, svcVer, schemaName, cname]
  print moduleName
  createHsBootFile cname moduleName schema
  createHsFile svcName svcVer cname moduleName imprtInfo schema

createHsBootFile :: RecordName -> ModuleName -> Schema -> IO ()
createHsBootFile name moduleName schema = do
  record <- Data.createBootData schema
  let path = FP.addExtension (T.unpack name) "hs-boot"
      content =
        flip T.snoc '\n'
          . unLines
          $ ["module " <> moduleName <> " where", "import Data.Aeson", record]
  B.writeFile path (T.encodeUtf8 content)

createHsFile
  :: ServiceName
  -> ServiceVersion
  -> RecordName
  -> ModuleName
  -> ImportInfo
  -> Schema
  -> IO ImportInfo
createHsFile svcName svcVer recName moduleName importInfo schema = do
  (record , jsonObjs) <- runWriterT $ Data.createData moduleName recName schema
  (records, imports ) <- runWriterT $ Data.createFieldData moduleName jsonObjs
  let path = FP.addExtension (T.unpack recName) "hs"
      importList =
        L.sort
          $  defaultImports
          <> createImports svcName svcVer recName importInfo imports
      content =
        flip T.snoc '\n'
          . unLines
          $ [ T.intercalate "\n" defaultExtentions
            , "module " <> moduleName <> " where"
            , T.intercalate "\n" importList
            , record
            , records
            ]
  B.writeFile path (T.encodeUtf8 content)
  pure $ ImportInfo.insert recName imports importInfo

createImports
  :: ServiceName
  -> ServiceVersion
  -> RecordName
  -> ImportInfo
  -> Set Import
  -> [Text]
createImports svcName svcVersion name importInfo = fmap f . Set.toList
 where
  f ImportPrelude  = "import RIO"
  f ImportEnum     = "import qualified RIO.Map as Map"
  f ImportGenerics = "import GHC.Generics()"
  f (Import recName) =
    let
      t = isCyclicImport name recName Set.empty importInfo
      s = if t then "{-# SOURCE #-} " else ""
      cname =
        fromMaybe recName . Map.lookup recName . importInfoRename $ importInfo
    in
      "import "
      <> s
      <> "qualified "
      <> svcName
      <> "."
      <> svcVersion
      <> "."
      <> schemaName
      <> "."
      <> cname
      <> " as "
      <> recName -- cname にしたいところ

isCyclicImport
  :: RecordName -> RecordName -> Set RecordName -> ImportInfo -> Bool
isCyclicImport name recName acc importInfo
  | Set.member rn acc = False
  | otherwise         = maybe False f $ ImportInfo.lookup recName importInfo
 where
  n  = T.toUpper name
  rn = T.toUpper recName
  f imports = imported || cyclicImport
   where
    imported = Set.member n imports
    cyclicImport =
      any (== True)
        . fmap (\r -> isCyclicImport name r (Set.insert rn acc) importInfo)
        $ Set.toList imports
