{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
module Test.JSON.Schema.Object where

import           RIO
import           RIO.Map                       as Map
import           Test.Tasty
import           Test.Tasty.Hspec
import           Text.RawString.QQ              ( r )
import           Data.Aeson                     ( decode )
import           JSON.Schema

{-# ANN module ("HLint: ignore Use camelCase" :: RIO.String) #-}

spec_Test_JSON_Schema_Object :: Spec
spec_Test_JSON_Schema_Object = describe "object" $ describe "Properties" $ do
  let
    json
      = [r|
          {
            "type": "object",
            "properties": {
              "number":      { "type": "number" },
              "street_name": { "type": "string" },
              "street_type": { "type": "string",
                               "enum": ["Street", "Avenue", "Boulevard"]
            }
          }
          }
        |]
    schema = Schema
      { schemaType        = Just (ObjectType objectType)
      , schemaTitle       = Nothing
      , schemaDescription = Nothing
      , schemaExamples    = Nothing
      , schemaComment     = Nothing
      , schemaEnum        = Nothing
      , schemaConst       = Nothing
      }
    propertiess = Map.fromList
      [ ( "number"
        , Schema
          (Just
            (NumberType (Number Nothing Nothing Nothing Nothing Nothing Nothing)
            )
          )
          Nothing
          Nothing
          Nothing
          Nothing
          Nothing
          Nothing
        )
      , ( "street_name"
        , Schema (Just (StringType (String Nothing Nothing Nothing Nothing)))
                 Nothing
                 Nothing
                 Nothing
                 Nothing
                 Nothing
                 Nothing
        )
      , ( "street_type"
        , Schema (Just (StringType (String Nothing Nothing Nothing Nothing)))
                 Nothing
                 Nothing
                 Nothing
                 Nothing
                 (Just ["Street", "Avenue", "Boulevard"])
                 Nothing
        )
      ]
    objectType = Object
      { objectProperties           = Just propertiess
      , objectAdditionalProperties = Nothing
      , objectRequired             = Nothing
      , objectPropertyNames        = Nothing
      , objectMinProperties        = Nothing
      , objectMaxProperties        = Nothing
      , objectDependencies         = Nothing
      , objectPatternProperties    = Nothing
      }
  it "Schema にエンコード" $ decode json `shouldBe` Just schema
  describe "additionalProperties bool" $ do
    let
      json
        = [r|
            {
              "type": "object",
              "properties": {
                "number":      { "type": "number" },
                "street_name": { "type": "string" },
                "street_type": { "type": "string",
                                 "enum": ["Street", "Avenue", "Boulevard"]
                               }
              },
              "additionalProperties": false
            }
          |]
      schema = Schema
        { schemaType        = Just (ObjectType objectType)
        , schemaTitle       = Nothing
        , schemaDescription = Nothing
        , schemaExamples    = Nothing
        , schemaComment     = Nothing
        , schemaEnum        = Nothing
        , schemaConst       = Nothing
        }
      propertiess = Map.fromList
        [ ( "number"
          , Schema
            (Just
              (NumberType
                (Number Nothing Nothing Nothing Nothing Nothing Nothing)
              )
            )
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
          )
        , ( "street_name"
          , Schema
            (Just (StringType (String Nothing Nothing Nothing Nothing)))
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
          )
        , ( "street_type"
          , Schema
            (Just (StringType (String Nothing Nothing Nothing Nothing)))
            Nothing
            Nothing
            Nothing
            Nothing
            (Just ["Street", "Avenue", "Boulevard"])
            Nothing
          )
        ]
      objectType = Object
        { objectProperties           = Just propertiess
        , objectAdditionalProperties = Just (AdditionalPropertiesBool False)
        , objectRequired             = Nothing
        , objectPropertyNames        = Nothing
        , objectMinProperties        = Nothing
        , objectMaxProperties        = Nothing
        , objectDependencies         = Nothing
        , objectPatternProperties    = Nothing
        }
    it "Schema にエンコード" $ decode json `shouldBe` Just schema
  describe "additionalProperties schema" $ do
    let
      json
        = [r|
            {
              "type": "object",
              "properties": {
                "number":      { "type": "number" },
                "street_name": { "type": "string" },
                "street_type": { "type": "string",
                                 "enum": ["Street", "Avenue", "Boulevard"]
                               }
              },
              "additionalProperties":  { "type": "string" }
            }
          |]
      schema = Schema
        { schemaType        = Just (ObjectType objectType)
        , schemaTitle       = Nothing
        , schemaDescription = Nothing
        , schemaExamples    = Nothing
        , schemaComment     = Nothing
        , schemaEnum        = Nothing
        , schemaConst       = Nothing
        }
      propertiess = Map.fromList
        [ ( "number"
          , Schema
            (Just
              (NumberType
                (Number Nothing Nothing Nothing Nothing Nothing Nothing)
              )
            )
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
          )
        , ( "street_name"
          , Schema
            (Just (StringType (String Nothing Nothing Nothing Nothing)))
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
          )
        , ( "street_type"
          , Schema
            (Just (StringType (String Nothing Nothing Nothing Nothing)))
            Nothing
            Nothing
            Nothing
            Nothing
            (Just ["Street", "Avenue", "Boulevard"])
            Nothing
          )
        ]
      objectType = Object
        { objectProperties           = Just propertiess
        , objectAdditionalProperties = Just
          (AdditionalPropertiesSchema
            (Schema
              (Just (StringType (String Nothing Nothing Nothing Nothing)))
              Nothing
              Nothing
              Nothing
              Nothing
              Nothing
              Nothing
            )
          )
        , objectRequired             = Nothing
        , objectPropertyNames        = Nothing
        , objectMinProperties        = Nothing
        , objectMaxProperties        = Nothing
        , objectDependencies         = Nothing
        , objectPatternProperties    = Nothing
        }
    it "Schema にエンコード" $ decode json `shouldBe` Just schema
