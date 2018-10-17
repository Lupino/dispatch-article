{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
module Article.API
  (
    getArticleById
  , updateArticle
  , updateArticleTitle
  , updateArticleSummary
  , updateArticleContent
  , updateArticleCover
  , updateArticleExtra
  , removeArticle
  , getArticleList
  , countArticle

  , createArticleAndFetch

  , toCardItem

  , addArticleTag
  , removeArticleTag
  , removeAllArticleTag

  , addTimeline
  , removeTimeline
  , removeTimelineListById
  , getArticleListByTimeline
  , countTimeline
  , module X
  ) where

import           Article.Config          (Cache, lruEnv, redisEnv)
import           Article.RawAPI          as X (addTag, existsArticle,
                                               getAllArticleTagName,
                                               getArticleIdList, getFileById,
                                               getFileWithKey, getTagById,
                                               getTagByName, getTimelineMeta,
                                               mergeData, removeTimelineMeta,
                                               saveFile, saveFileWithExtra,
                                               saveTimelineMeta, updateTag)
import qualified Article.RawAPI          as RawAPI
import           Article.Types
import           Article.Utils           (cleanHtml, firstImage)
import           Data.Aeson              (Value)
import           Data.ByteString         (ByteString)
import           Data.Int                (Int64)
import           Data.Maybe              (catMaybes, isJust)
import           Data.String             (fromString)
import           Data.Traversable        (for)
import           Haxl.Core               (GenHaxl)
import           System.FilePath         (takeFileName)
import           Yuntan.Extra.Config     (fillValue_)
import           Yuntan.Types.HasMySQL   (HasMySQL, HasOtherEnv)
import           Yuntan.Types.ListResult (From, Size)
import           Yuntan.Types.OrderBy    (OrderBy)
import           Yuntan.Utils.RedisCache (cached, cached', remove)

genArticleKey :: ID -> ByteString
genArticleKey id0 = fromString $ "article:" ++ show id0

genCountKey :: String -> ByteString
genCountKey k = fromString $ "count:" ++ k

($>) :: GenHaxl u a -> GenHaxl u () -> GenHaxl u a
io $> a = do
  !r <- io
  !_ <- a
  return r

unCacheCount :: HasOtherEnv Cache u => String -> GenHaxl u a -> GenHaxl u a
unCacheCount k io = io $> remove redisEnv (genCountKey k)

unCacheTimelineCount :: HasOtherEnv Cache u => [String] -> GenHaxl u ()
unCacheTimelineCount = mapM_ (\k -> remove redisEnv (genCountKey ("timeline:" ++ k)))

unCacheArticle :: HasOtherEnv Cache u => ID -> GenHaxl u a -> GenHaxl u a
unCacheArticle id0 io = io $> remove redisEnv (genArticleKey id0)

createArticle
  :: (HasMySQL u, HasOtherEnv Cache u)
  => Title -> Summary -> Content -> FromURL -> CreatedAt -> GenHaxl u ID
createArticle t s c f ct =
  unCacheCount "article" $ RawAPI.createArticle t s c f ct

getArticleById :: (HasMySQL u, HasOtherEnv Cache u) => ID -> GenHaxl u (Maybe Article)
getArticleById artId =
  cached redisEnv (genArticleKey artId) $
    fillArticle =<< RawAPI.getArticleById artId

fillArticle :: (HasMySQL u, HasOtherEnv Cache u) => Maybe Article -> GenHaxl u (Maybe Article)
fillArticle Nothing = return Nothing
fillArticle (Just art) =
  fmap Just
    $ fillArticleExtra
    =<< fillAllTimeline
    =<< fillArticleCover
    =<< fillAllTagName art

updateArticle :: (HasMySQL u, HasOtherEnv Cache u) => ID -> Title -> Summary -> Content -> GenHaxl u Int64
updateArticle artId t s c = unCacheArticle artId $ RawAPI.updateArticle artId t s c

updateArticleTitle :: (HasMySQL u, HasOtherEnv Cache u) => ID -> Title -> GenHaxl u Int64
updateArticleTitle artId t = unCacheArticle artId $ RawAPI.updateArticleTitle artId t

updateArticleSummary :: (HasMySQL u, HasOtherEnv Cache u) => ID -> Summary -> GenHaxl u Int64
updateArticleSummary artId s = unCacheArticle artId $ RawAPI.updateArticleSummary artId s

updateArticleContent :: (HasMySQL u, HasOtherEnv Cache u) => ID -> Content -> GenHaxl u Int64
updateArticleContent artId c = unCacheArticle artId $ RawAPI.updateArticleContent artId c

updateArticleCover :: (HasMySQL u, HasOtherEnv Cache u) => ID -> Maybe File -> GenHaxl u Int64
updateArticleCover artId cover = unCacheArticle artId $ RawAPI.updateArticleCover artId cover

fillArticleCover :: HasMySQL u => Article -> GenHaxl u Article
fillArticleCover art = do
  file <- if isJust cover then return cover else getFileWithKey key
  return art { artCover = file }

  where cover = artCover art
        key   = takeFileKey . firstImage $ artSummary art

updateArticleExtra :: (HasMySQL u, HasOtherEnv Cache u) => ID -> Value -> GenHaxl u Int64
updateArticleExtra artId extra = unCacheArticle artId $ RawAPI.updateArticleExtra artId extra

getArticleList
  :: (HasMySQL u, HasOtherEnv Cache u)
  => From -> Size -> OrderBy -> GenHaxl u [Article]
getArticleList f s o = do
  aids <- RawAPI.getArticleIdList f s o
  catMaybes <$> for aids getArticleById

countArticle :: (HasMySQL u, HasOtherEnv Cache u) => GenHaxl u Int64
countArticle = cached' redisEnv (genCountKey "article") RawAPI.countArticle

removeArticle :: (HasMySQL u, HasOtherEnv Cache u) => ID -> GenHaxl u Int64
removeArticle artId =
  unCacheArticle artId $ unCacheCount "article" $ RawAPI.removeArticle artId

createArticleAndFetch
  :: (HasMySQL u, HasOtherEnv Cache u)
  => Title -> Summary -> Content -> FromURL -> CreatedAt -> GenHaxl u (Maybe Article)
createArticleAndFetch t s co f c = getArticleById =<< createArticle t s co f c

toCardItem :: HasMySQL u => Article -> GenHaxl u CardItem
toCardItem art = do
  file <- if isJust cover then return cover else getFileWithKey key
  return CardItem { cardID         = cid
                  , cardTitle      = title
                  , cardSummary    = summary
                  , cardImage      = file
                  , cardTags       = tags
                  , cardExtra      = extra
                  , cardCreatedAt  = created
                  }

  where cid           = artID art
        title         = take 10 $ artTitle art
        summary       = take 50 $ cleanHtml $ artSummary art

        key     = takeFileKey . firstImage $ artSummary art
        cover   = artCover art
        tags    = artTags art
        extra   = artExtra art
        created = artCreatedAt art

takeFileKey :: String -> String
takeFileKey = takeWhile (/= '.') . takeFileName . takeWhile (/= '?')

addArticleTag :: (HasMySQL u, HasOtherEnv Cache u) => ID -> ID -> GenHaxl u ID
addArticleTag aid tid  = unCacheArticle aid $ RawAPI.addArticleTag aid tid

removeArticleTag :: (HasMySQL u, HasOtherEnv Cache u) => ID -> ID -> GenHaxl u Int64
removeArticleTag aid tid = unCacheArticle aid $ RawAPI.removeArticleTag aid tid

removeAllArticleTag  :: (HasMySQL u, HasOtherEnv Cache u) => ID -> GenHaxl u Int64
removeAllArticleTag aid  = unCacheArticle aid $ RawAPI.removeAllArticleTag aid

fillAllTagName :: HasMySQL u => Article -> GenHaxl u Article
fillAllTagName art = do
  tags <- RawAPI.getAllArticleTagName $ artID art
  return $ art { artTags = tags }

addTimeline :: (HasMySQL u, HasOtherEnv Cache u) => String -> ID -> GenHaxl u ID
addTimeline name aid = unCacheArticle aid $ RawAPI.addTimeline name aid

removeTimeline :: (HasMySQL u, HasOtherEnv Cache u) => String -> ID -> GenHaxl u Int64
removeTimeline name aid =
  unCacheArticle aid $ unCacheCount ("timeline:" ++ name) $ RawAPI.removeTimeline name aid

removeTimelineListById :: (HasMySQL u, HasOtherEnv Cache u) => ID -> GenHaxl u Int64
removeTimelineListById aid = unCacheArticle aid $ do
  names <- RawAPI.getTimelineListById aid
  r <- RawAPI.removeTimelineListById aid
  unCacheTimelineCount names
  pure r

getArticleListByTimeline
  :: (HasMySQL u, HasOtherEnv Cache u)
  => String -> From -> Size -> OrderBy -> GenHaxl u [Article]
getArticleListByTimeline name f s o    = do
  aids <- RawAPI.getIdListByTimeline name f s o
  catMaybes <$> for aids getArticleById

countTimeline :: (HasMySQL u, HasOtherEnv Cache u) => String -> GenHaxl u Int64
countTimeline name =
  cached' redisEnv (genCountKey ("timeline:" ++ name)) $ RawAPI.countTimeline name

fillAllTimeline :: HasMySQL u => Article -> GenHaxl u Article
fillAllTimeline art = do
  timelines <- RawAPI.getTimelineListById $ artID art
  return $ art { artTimelines = timelines }

fillArticleExtra :: (HasMySQL u, HasOtherEnv Cache u) => Article -> GenHaxl u Article
fillArticleExtra = fillValue_ lruEnv "article-extra" artExtra update
  where update :: Value -> Article -> Article
        update v u = u {artExtra = v}
