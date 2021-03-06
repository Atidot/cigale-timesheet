{-# LANGUAGE RecursiveDo, TupleSections #-}

module ConfigWidgets where

import GHCJS.DOM.HTMLInputElement
import GHCJS.DOM.Types (fromJSString)

import Reflex.Class
import Reflex.Dynamic
import Reflex.Dom hiding (display, Value)
import Clay as C hiding (map, (&), filter, head, p, url, active,
                         name, pc, id, intersperse, reverse, Value)

import Data.Monoid
import Data.Maybe
import Data.List
import Data.Function
import Control.Monad.IO.Class
import qualified Data.Text as T
import qualified Data.Vector as V
import Data.Aeson as A
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Bool (bool)

import Common
import FilePicker

fileEntry :: MonadWidget t m => PickerOperationMode -> String -> String -> String -> String
          -> m (Dynamic t String)
fileEntry pickerOpMode _ memberName memberLabel val = do
    elAttr "label" ("for" =: memberName) $ text memberLabel
    elAttr "div" ("class" =: "input-group") $ do
        rec
            let inputAttrs = "id" =: memberName <> "class" =: "form-control"
            inputVal <- _textInput_value <$> textInput
                (def
                 & textInputConfig_attributes .~ constDyn inputAttrs
                 & textInputConfig_initialValue .~ val
                 & textInputConfig_setValue .~ updatedFilePath)
            (browseBtn, _) <- elAttr' "div" ("class" =: "input-group-addon") $
                elStyle' "span" (cursor pointer) $ text "Browse..."
            updatedFilePath <- buildFilePicker
                pickerDefaultOptions { pickerMode = pickerOpMode }
                (tagDyn inputVal $ domEvent Click browseBtn)
        return inputVal

fieldEntry :: MonadWidget t m => String -> String -> String -> m (Dynamic t String)
fieldEntry fieldId desc fieldValue = do
    elAttr "label" ("for" =: fieldId) $ text desc
    _textInput_value <$> textInput
        (def
         & textInputConfig_attributes .~ constDyn ("id" =: fieldId <> "class" =: "form-control")
         & textInputConfig_initialValue .~ fieldValue)

passwordEntry :: MonadWidget t m => String -> String -> String -> m (Dynamic t String)
passwordEntry fieldId desc fieldValue = do
    elAttr "label" ("for" =: fieldId) $ text desc
    elAttr "div" ("class" =: "input-group") $ do
        rec
            attrsDyn <- forDyn showPaswd $ \p ->
                "class" =: "form-control" <>
                "id"    =: fieldId <>
                "value" =: fieldValue <>
                "type"  =: if p then "password" else "text"
            (inputField, _) <- elDynAttr' "input" attrsDyn $ return ()
            showPaswd <- toggle True (domEvent Click padlock)
            (padlock, _) <- elAttr' "div" ("class" =: "input-group-addon") $
                rawPointerSpan =<< forDyn showPaswd (bool "&#128275;" "&#128274;")
        let getFieldValue = liftIO $ do
                val <- getValue (castToHTMLInputElement $ _el_element inputField)
                return $ fromMaybe "" $ fromJSString <$> val
        holdDyn fieldValue =<< performEvent
            (const getFieldValue <$> domEvent Change inputField)

toDynValue :: MonadWidget t m => Dynamic t String -> m (Dynamic t Value)
toDynValue = mapDyn (A.String . T.pack)

-- i have to give a map to reflex, and it sorts -- I want
-- case insensitive sorting so I have no choice but this.
-- probably should rather use int for the key or something...
newtype CaseFoldString = CaseFoldString { unCaseFold :: String } deriving (Show, Read)

cfsToCaseFold :: CaseFoldString -> T.Text
cfsToCaseFold = T.toCaseFold . T.pack . unCaseFold

instance Ord CaseFoldString where
    compare = compare `on` cfsToCaseFold
instance Eq CaseFoldString where
    (==) = (==) `on` cfsToCaseFold

comboEntry :: MonadWidget t m => Dynamic t (Map String [String])
           -> String -> String -> String
           -> m (Dynamic t String)
comboEntry fieldContentsDyn memberName memberLabel fieldValue = do
    let toKeyVal x = (CaseFoldString x,x)
    let prepareComboCts = Map.fromList . map toKeyVal . fromJust . Map.lookup memberName
    itemsDyn <- mapDyn prepareComboCts fieldContentsDyn
    elAttr "label" ("for" =: memberName) $ text memberLabel
    elAttr "div" ("class" =: "input-group") $ do
        val <- _dropdown_value <$> dropdown (CaseFoldString fieldValue) itemsDyn
            (def & dropdownConfig_attributes .~ constDyn ("class" =: "form-control"))
        mapDyn unCaseFold val

multiChoiceEntry :: MonadWidget t m => Dynamic t (Map String [String])
           -> String -> String -> Maybe Value
           -> m (Dynamic t Value)
multiChoiceEntry fieldContentsDyn memberName memberLabel fieldValue = do
    evtDyn <- dyn =<< mapDyn
        (multiChoiceEntry_ memberName memberLabel fieldValue)
        (nubDyn fieldContentsDyn)
    joinDyn <$> holdDyn (constDyn $ A.Array V.empty) evtDyn

multiChoiceEntry_ :: MonadWidget t m => String -> String -> Maybe Value
           -> Map String [String]
           -> m (Dynamic t Value)
multiChoiceEntry_ memberName memberLabel fieldValue fieldContents = do
    let active = fromMaybe [] (valueToStrList =<< fieldValue)
    el "label" $ text memberLabel
    let valueList = fromJust $ Map.lookup memberName fieldContents
    elStyle "div" (overflow auto >> height (px 150)) $ do
        rec
            currentSelection <- foldDyn
                (\(isOn, val) values ->
                   if isOn
                   then val : values
                   else delete val values) active clickedCbEvt
            clickedCbEvt <- leftmost <$> mapM (singleCb currentSelection) valueList
        mapDyn strListToValue currentSelection

valueToStr :: Value -> Maybe String
valueToStr (A.String v) = Just (T.unpack v)
valueToStr _ = Nothing

valueToStrList :: Value -> Maybe [String]
valueToStrList (A.Array ar) = V.toList <$> sequence (valueToStr <$> ar)
valueToStrList _ = Nothing

strListToValue :: [String] -> Value
strListToValue = A.Array . V.fromList . fmap (A.String . T.pack)

singleCb :: MonadWidget t m => Dynamic t [String] -> String -> m (Event t (Bool, String))
singleCb activeListDyn txt = do
    isActiveDyn <- mapDyn (elem txt) activeListDyn
    cbEvt <- el "label" (checkboxView (constDyn Map.empty) isActiveDyn <* text txt)
    el "br" (return ())
    return $ fmap (, txt) cbEvt
