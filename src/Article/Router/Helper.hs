{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
module Article.Router.Helper
  (
    pageParam
  , timeline
  , timelineTitle
  , timelineMeta
  , articles
  , article
  , requireArticle
  , requireTag
  , requireTagAndArticle
  , resultOK
  , extraKeys
  , preprocessArticle
  , preprocessArticleList
  ) where

import           Article
import           Article.Config          (Cache)
import           Control.Monad.Reader    (lift)
import           Data.Int                (Int64)
import           Data.String.Utils       (split)
import           Data.Text               (Text, pack)
import           Haxl.Core               (GenHaxl)
import           Web.Scotty.Trans        (param)
import           Yuntan.Types.HasMySQL   (HasMySQL, HasOtherEnv)
import           Yuntan.Types.ListResult (From, ListResult (..), Size,
                                          emptyListResult)
import           Yuntan.Types.OrderBy    (desc)
import           Yuntan.Types.Scotty     (ActionH)
import           Yuntan.Utils.Scotty     (errNotFound, ok, safeParam)

pageParam :: ActionH u (Int64, Int64)
pageParam = do
  page <- safeParam "page" (1 :: Int64)
  from <- safeParam "from" (0 :: Int64)
  size <- safeParam "size" 10
  return (max ((page - 1) * size) from, size)

timelineMeta :: HasMySQL u => String -> ActionH u (Maybe (Title, Summary))
timelineMeta = lift . getTimelineMeta

timelineTitle :: HasMySQL u => String -> ActionH u Title
timelineTitle name = maybe name fst <$> timelineMeta name

timeline :: (HasMySQL u, HasOtherEnv Cache u) => String -> ActionH u (ListResult Article)
timeline name = articles' s t
  where s = flip' (getArticleListByTimeline name) $ desc "art_id"
        t = countTimeline name

articles :: (HasMySQL u, HasOtherEnv Cache u) => ActionH u (ListResult Article)
articles = articles' s t
  where s = flip' getArticleList $ desc "id"
        t = countArticle

flip' :: (a -> b -> c -> d) -> c -> a -> b -> d
flip' f = g
  where g c a b = f a b c


articles' :: HasMySQL u => (From -> Size -> GenHaxl u [Article]) -> GenHaxl u Int64 -> ActionH u (ListResult Article)
articles' s t = do
  (from, size) <- pageParam
  lift $ do
    arts <- s from size
    total <- t

    return emptyListResult { getResult = arts
                           , getFrom   = from
                           , getSize   = size
                           , getTotal  = total
                           }

article :: (HasMySQL u, HasOtherEnv Cache u) => ActionH u (Maybe Article)
article = do
  aid <- param "art_id"
  lift $ getArticleById aid

requireArticle :: (HasMySQL u, HasOtherEnv Cache u) => (Article -> ActionH u ()) -> ActionH u ()
requireArticle action = do
  artId <- param "art_id"

  art <- lift $ getArticleById artId
  maybe (notFound artId) action art

  where notFound artId = errNotFound $ concat [ "Article (", show artId, ") not found" ]

requireTag :: HasMySQL u => (Tag -> ActionH u ()) -> ActionH u ()
requireTag action = do
  tid <- safeParam "tag_id" (0::ID)
  name <- safeParam "tag" (""::String)

  tag <- lift $
    if tid > 0 then getTagById tid
               else getTagByName name

  maybe notFound action tag
  where notFound = errNotFound "Not Found."

merge :: Monad m => ((a -> m ()) -> m ()) -> ((b -> m ()) -> m ()) -> (a -> b -> m ()) -> m ()
merge f g t = f $ \a -> g $ \b -> t a b

requireTagAndArticle :: (HasMySQL u, HasOtherEnv Cache u) => (Tag -> Article -> ActionH u ()) -> ActionH u ()
requireTagAndArticle = merge requireTag requireArticle

resultOK :: ActionH u ()
resultOK = ok "result" ("OK" :: Text)

extraKeys :: ActionH u [Text]
extraKeys = do
  ks <- safeParam "extra_keys" (""::String)

  if null ks then return []
             else return . map pack $ split "," ks

contentKeys :: ActionH u [Text]
contentKeys = do
  ks <- safeParam "content_keys" (""::String)

  if null ks then return []
             else return . map pack $ split "," ks

isJsonContent :: ActionH u Bool
isJsonContent = not . null <$> safeParam "content_json" ("" :: String)

preprocessArticle :: Article -> ActionH u Article
preprocessArticle = checkExtraKeys $ checkJsonContent $ checkContentKeys return
  where checkExtraKeys :: (Article -> ActionH u Article) -> Article -> ActionH u Article
        checkExtraKeys next a = next =<< (flip pickExtra a <$> extraKeys)

        checkJsonContent :: (Article -> ActionH u Article) -> Article -> ActionH u Article
        checkJsonContent next a = do
          isJson <- isJsonContent
          if isJson then next (setJsonContent a) else next a

        checkContentKeys :: (Article -> ActionH u Article) -> Article -> ActionH u Article
        checkContentKeys next a = do
          keys <- contentKeys
          if null keys then next a else next (pickContent keys a)

preprocessArticleList :: [Article] -> ActionH u [Article]
preprocessArticleList = mapM preprocessArticle
