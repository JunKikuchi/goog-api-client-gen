{-# LANGUAGE OverloadedStrings #-}
module Generator.Schema.File
  ( gen
  , schemaName
  )
where

import           Prelude                        ( print )

import           RIO
import qualified RIO.ByteString                as B
import qualified RIO.FilePath                  as FP
import qualified RIO.List                      as L
import qualified RIO.Text                      as T
import           RIO.Writer                     ( runWriterT )
import           Discovery.RestDescription
import           Generator.Types
import           Generator.Util
import qualified Generator.Schema.Content      as C
import           Generator.Schema.ImportInfo    ( ImportInfo )
import qualified Generator.Schema.ImportInfo   as ImportInfo
import           Generator.Schema.Types  hiding ( Schema )

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
gen svcName svcVer schemas = withDir schemaDir
  $ foldM_ (createFile svcName svcVer) ImportInfo.empty schemas

createFile
  :: ServiceName -> ServiceVersion -> ImportInfo -> Schema -> IO ImportInfo
createFile svcName svcVer importInfo schema = do
  name <- get schemaId "schemaId" schema
  let (cname, newImportInfo) = ImportInfo.canonicalName name importInfo
      moduleName = T.intercalate "." [svcName, svcVer, schemaName, cname]
  print moduleName
  createHsBootFile cname moduleName schema
  createHsFile svcName svcVer cname moduleName schema newImportInfo

createHsBootFile :: RecordName -> ModuleName -> Schema -> IO ()
createHsBootFile recName moduleName schema = do
  record <- C.createBootContent schema
  let path = FP.addExtension (T.unpack recName) "hs-boot"
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
  -> Schema
  -> ImportInfo
  -> IO ImportInfo
createHsFile svcName svcVer recName moduleName schema importInfo = do
  (record , jsonObjs) <- runWriterT $ C.createContent moduleName recName schema
  (records, imports ) <- runWriterT $ C.createFieldContent moduleName jsonObjs
  let path = FP.addExtension (T.unpack recName) "hs"
      importList =
        L.sort
          $  defaultImports
          <> ImportInfo.createImports svcName
                                      svcVer
                                      schemaName
                                      recName
                                      importInfo
                                      imports
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
