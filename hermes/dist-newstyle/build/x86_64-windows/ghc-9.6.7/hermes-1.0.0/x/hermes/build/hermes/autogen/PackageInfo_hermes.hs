{-# LANGUAGE NoRebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
{-# OPTIONS_GHC -w #-}
module PackageInfo_hermes (
    name,
    version,
    synopsis,
    copyright,
    homepage,
  ) where

import Data.Version (Version(..))
import Prelude

name :: String
name = "hermes"
version :: Version
version = Version [1,0,0] []

synopsis :: String
synopsis = "HERMES - Satelite de Retransmision SHA-256"
copyright :: String
copyright = ""
homepage :: String
homepage = ""
