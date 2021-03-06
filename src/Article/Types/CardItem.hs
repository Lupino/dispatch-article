{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
module Article.Types.CardItem
  ( CardItem(..)
  ) where

import           Article.Types.Internal
import           Article.Types.PSQL.File
import           Data.Aeson              (ToJSON (..), Value (..), object, (.=))

data CardItem = CardItem
  { cardID        :: ID
  , cardTitle     :: Title
  , cardSummary   :: Summary
  , cardImage     :: Maybe File
  , cardTags      :: [TagName]
  , cardExtra     :: Value
  , cardCreatedAt :: CreatedAt
  }

instance ToJSON CardItem where
  toJSON CardItem{..} = object
    [ "id"         .= cardID
    , "title"      .= cardTitle
    , "summary"    .= cardSummary
    , "file"       .= cardImage
    , "tags"       .= cardTags
    , "extra"      .= cardExtra
    , "created_at" .= cardCreatedAt
    ]
