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

createFile
  :: ServiceName -> ServiceVersion -> ImportInfo -> Schema -> IO ImportInfo
createFile svcName svcVer importInfo schema = do
  name <- get schemaId "schemaId" schema

  let moduleName = T.intercalate "." [svcName, svcVer, schemaName, name]
  print moduleName

  createHsBootFile name moduleName schema
  createHsFile svcName svcVer name moduleName importInfo schema

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
createHsFile svcName svcVer name moduleName importInfo schema = do
  (record , jsonObjs) <- runWriterT $ Data.createData moduleName schema
  (records, imports ) <- runWriterT $ Data.createFieldData moduleName jsonObjs
  let path = FP.addExtension (T.unpack name) "hs"
      importList =
        L.sort
          $  defaultImports
          <> createImports svcName svcVer name importInfo imports
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
  pure $ mergeImports name imports importInfo

mergeImports :: RecordName -> Set Import -> ImportInfo -> ImportInfo
mergeImports name imports importInfo | Set.null names = importInfo
                                     | otherwise = Map.union imptInfo importInfo
 where
  names = Set.map (T.toUpper . unImport) . Set.filter filterRecord $ imports
  unImport :: Import -> Text
  unImport (Import impt) = T.toUpper impt
  unImport _             = undefined
  filterRecord :: Import -> Bool
  filterRecord (Import _) = True
  filterRecord _          = False
  imptInfo = Map.singleton (T.toUpper name) imptDetail
  imptDetail =
    ImportDetail {importDetailImports = names, importDetailRename = Nothing}

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
    let t = isCyclicImport name recName Set.empty importInfo
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
        <> recName
        <> " as "
        <> recName

isCyclicImport
  :: RecordName -> RecordName -> Set RecordName -> ImportInfo -> Bool
isCyclicImport name recName acc importInfo
  | Set.member rn acc = False
  | otherwise         = maybe False f $ Map.lookup rn importInfo
 where
  n  = T.toUpper name
  rn = T.toUpper recName
  f impDetail = imported || cyclicImport
   where
    imported = Set.member n impts
    cyclicImport =
      any (== True)
        . fmap (\r -> isCyclicImport name r (Set.insert rn acc) importInfo)
        $ Set.toList impts
    impts = importDetailImports impDetail
