-- -*- coding: utf-8; mode: haskell; -*-

-- File: library/Language/Ninja/IR/Ninja.hs
--
-- License:
--     Copyright 2017 Awake Security
--
--     Licensed under the Apache License, Version 2.0 (the "License");
--     you may not use this file except in compliance with the License.
--     You may obtain a copy of the License at
--
--       http://www.apache.org/licenses/LICENSE-2.0
--
--     Unless required by applicable law or agreed to in writing, software
--     distributed under the License is distributed on an "AS IS" BASIS,
--     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--     See the License for the specific language governing permissions and
--     limitations under the License.

{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE UndecidableInstances  #-}

-- |
--   Module      : Language.Ninja.IR.Ninja
--   Copyright   : Copyright 2017 Awake Security
--   License     : Apache-2.0
--   Maintainer  : opensource@awakesecurity.com
--   Stability   : experimental
--
--   A datatype representing the intermediate representation of a Ninja file
--   after compilation.
--
--   @since 0.1.0
module Language.Ninja.IR.Ninja
  ( -- * @Ninja@
    Ninja, makeNinja
  , ninjaMeta, ninjaBuilds, ninjaPhonys, ninjaDefaults, ninjaPools
  , NinjaConstraint
  ) where

import qualified Control.Lens             as Lens

import           Data.Text                (Text)

import           Data.HashMap.Strict      (HashMap)
import qualified Data.HashMap.Strict      as HM

import           Data.HashSet             (HashSet)
import qualified Data.HashSet             as HS

import           Data.Aeson               ((.:), (.=))
import qualified Data.Aeson               as Aeson

import qualified Data.Versions            as Ver

import           Control.DeepSeq          (NFData)
import           Data.Hashable            (Hashable)
import           GHC.Generics             (Generic)
import qualified Test.SmallCheck.Series   as SC

import           GHC.Exts                 (Constraint)
import           Data.Kind                (Type)

import           Language.Ninja.IR.Build  (Build)
import           Language.Ninja.IR.Meta   (Meta)
import qualified Language.Ninja.IR.Meta   as Ninja
import           Language.Ninja.IR.Pool   (Pool)
import           Language.Ninja.IR.Target (Target)

import           Flow                     ((|>))

--------------------------------------------------------------------------------

-- | A parsed and normalized Ninja file.
--
--   @since 0.1.0
data Ninja
  = MkNinja
    { _ninjaMeta     :: !Meta
    , _ninjaBuilds   :: !(HashSet Build)
    , _ninjaPhonys   :: !(HashMap Target (HashSet Target))
    , _ninjaDefaults :: !(HashSet Target)
    , _ninjaPools    :: !(HashSet Pool)
    }
  deriving (Eq, Show, Generic)

-- | Construct a default 'Ninja' value.
--
--   @since 0.1.0
{-# INLINE makeNinja #-}
makeNinja :: Ninja
makeNinja = MkNinja
            { _ninjaMeta     = Ninja.makeMeta
            , _ninjaBuilds   = HS.empty
            , _ninjaPhonys   = HM.empty
            , _ninjaDefaults = HS.empty
            , _ninjaPools    = HS.empty
            }

-- | Metadata, which includes top-level variables like @builddir@.
--
--   @since 0.1.0
{-# INLINE ninjaMeta #-}
ninjaMeta :: Lens.Lens' Ninja Meta
ninjaMeta = Lens.lens _ninjaMeta
            $ \(MkNinja {..}) x -> MkNinja { _ninjaMeta = x, .. }

-- | Compiled @build@ declarations.
--
--   @since 0.1.0
{-# INLINE ninjaBuilds #-}
ninjaBuilds :: Lens.Lens' Ninja (HashSet Build)
ninjaBuilds = Lens.lens _ninjaBuilds
              $ \(MkNinja {..}) x -> MkNinja { _ninjaBuilds = x, .. }

-- | Phony targets, as documented
--   <https://ninja-build.org/manual.html#_more_details here>.
--
--   @since 0.1.0
{-# INLINE ninjaPhonys #-}
ninjaPhonys :: Lens.Lens' Ninja (HashMap Target (HashSet Target))
ninjaPhonys = Lens.lens _ninjaPhonys
              $ \(MkNinja {..}) x -> MkNinja { _ninjaPhonys = x, .. }

-- | The set of default targets, as documented
--   <https://ninja-build.org/manual.html#_default_target_statements here>.
--
--   @since 0.1.0
{-# INLINE ninjaDefaults #-}
ninjaDefaults :: Lens.Lens' Ninja (HashSet Target)
ninjaDefaults = Lens.lens _ninjaDefaults
                $ \(MkNinja {..}) x -> MkNinja { _ninjaDefaults = x, .. }

-- | The set of pools for this Ninja file.
--
--   @since 0.1.0
{-# INLINE ninjaPools #-}
ninjaPools :: Lens.Lens' Ninja (HashSet Pool)
ninjaPools = Lens.lens _ninjaPools
             $ \(MkNinja {..}) x -> MkNinja { _ninjaPools = x, .. }

-- | Converts to @{meta: …, builds: …, phonys: …, defaults: …, pools: …}@.
--
--   @since 0.1.0
instance Aeson.ToJSON Ninja where
  toJSON (MkNinja {..})
    = [ "meta"     .= _ninjaMeta
      , "builds"   .= _ninjaBuilds
      , "phonys"   .= _ninjaPhonys
      , "defaults" .= _ninjaDefaults
      , "pools"    .= _ninjaPools
      ] |> Aeson.object

-- | Inverse of the 'Aeson.ToJSON' instance.
--
--   @since 0.1.0
instance Aeson.FromJSON Ninja where
  parseJSON = (Aeson.withObject "Ninja" $ \o -> do
                  _ninjaMeta     <- (o .: "meta")     >>= pure
                  _ninjaBuilds   <- (o .: "builds")   >>= pure
                  _ninjaPhonys   <- (o .: "phonys")   >>= pure
                  _ninjaDefaults <- (o .: "defaults") >>= pure
                  _ninjaPools    <- (o .: "pools")    >>= pure
                  pure (MkNinja {..}))

-- | Default 'Hashable' instance via 'Generic'.
--
--   @since 0.1.0
instance Hashable Ninja

-- | Default 'NFData' instance via 'Generic'.
--
--   @since 0.1.0
instance NFData Ninja

-- | Default 'SC.Serial' instance via 'Generic'.
--
--   @since 0.1.0
instance (Monad m, NinjaConstraint (SC.Serial m)) => SC.Serial m Ninja

-- | Default 'SC.CoSerial' instance via 'Generic'.
--
--   @since 0.1.0
instance (Monad m, NinjaConstraint (SC.CoSerial m)) => SC.CoSerial m Ninja

-- | The set of constraints required for a given constraint to be automatically
--   computed for a 'Ninja'.
--
--   @since 0.1.0
type NinjaConstraint (c :: Type -> Constraint)
  = ( c Text
    , c Ver.Version
    , c (HashMap Target (HashSet Target))
    , c (HashSet Build)
    , c (HashSet Target)
    , c (HashSet Pool)
    )

--------------------------------------------------------------------------------
