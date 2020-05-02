{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
module Discovery where

import           RIO
import           Network.HTTP.Client            ( newManager )
import           Network.HTTP.Client.TLS        ( tlsManagerSettings )
import           Servant.API
import           Servant.Client                 ( BaseUrl(..)
                                                , Scheme(Https)
                                                , ClientM
                                                , ClientError
                                                , client
                                                , mkClientEnv
                                                , runClientM
                                                )
import           Data.Aeson                     ( Value )

type Name = Text
type Preferred = Bool
type Api = Text
type Version = Text

baseUrl :: BaseUrl
baseUrl = BaseUrl Https "www.googleapis.com" 443 ""

type API
     = "discovery" :> "v1" :> "apis"
       :> QueryParam "name" Name
       :> QueryParam "preferred" Preferred
       :> Get '[JSON] Value
  :<|> "discovery" :> "v1" :> "apis" :> Capture "api" Api :> Capture "version" Version :> "rest"
       :> Get '[JSON] Value

api :: Proxy API
api = Proxy

list :: Maybe Name -> Maybe Preferred -> ClientM Value
getRest :: Api -> Version -> ClientM Value
(list :<|> getRest) = client api

run :: ClientM a -> IO (Either ClientError a)
run client = do
  manager <- newManager tlsManagerSettings
  runClientM client (mkClientEnv manager baseUrl)
