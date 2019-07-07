module UI.Tracks exposing (initialModel, makeParcel, resolveParcel, update, view)

import Alien
import Chunky exposing (..)
import Classes as C
import Color exposing (Color)
import Color.Ext as Color
import Common exposing (Switch(..))
import Coordinates
import Css
import Css.Transitions exposing (transition)
import Html.Events.Extra.Mouse as Mouse
import Html.Styled as Html exposing (Html, text)
import Html.Styled.Attributes exposing (css, fromUnstyled, placeholder, tabindex, title, value)
import Html.Styled.Events exposing (onBlur, onClick, onInput)
import Html.Styled.Ext exposing (onEnterKey)
import Html.Styled.Lazy exposing (..)
import InfiniteList
import Json.Decode as Json
import Json.Encode
import List.Ext as List
import List.Extra as List
import Material.Icons exposing (Coloring(..))
import Material.Icons.Action as Icons
import Material.Icons.Av as Icons
import Material.Icons.Communication as Icons
import Material.Icons.Content as Icons
import Material.Icons.Editor as Icons
import Material.Icons.Image as Icons
import Material.Icons.Navigation as Icons
import Maybe.Extra as Maybe
import Playlists exposing (Playlist)
import Return3 as Return exposing (..)
import Tachyons.Classes as T
import Task.Extra as Task
import Tracks exposing (..)
import Tracks.Collection as Collection exposing (..)
import Tracks.Encoding as Encoding
import Tracks.Favourites as Favourites
import UI.Core
import UI.DnD as DnD
import UI.Kit
import UI.Navigation exposing (..)
import UI.Page exposing (Page)
import UI.Playlists.Page
import UI.Ports
import UI.Queue.Page
import UI.Reply exposing (Reply(..))
import UI.Tracks.Core exposing (..)
import UI.Tracks.Scene.List



-- 🌳


initialModel : Model
initialModel =
    { collection = emptyCollection
    , enabledSourceIds = []
    , favourites = []
    , favouritesOnly = False
    , grouping = Nothing
    , hideDuplicates = False
    , nowPlaying = Nothing
    , scene = List
    , searchResults = Nothing
    , searchTerm = Nothing
    , selectedPlaylist = Nothing
    , selectedTrackIndexes = []
    , sortBy = Artist
    , sortDirection = Asc

    -----------------------------------------
    -- Scenes / List
    -----------------------------------------
    , infiniteList = InfiniteList.init
    , listDnD = DnD.initialModel
    }



-- 📣


update : Msg -> Model -> Return Model Msg Reply
update msg model =
    case msg of
        Bypass ->
            return model

        MarkAsSelected indexInList { shiftKey } ->
            let
                selection =
                    if shiftKey then
                        model.selectedTrackIndexes
                            |> List.head
                            |> Maybe.map
                                (\n ->
                                    if n > indexInList then
                                        List.range indexInList n

                                    else
                                        List.range n indexInList
                                )
                            |> Maybe.withDefault [ indexInList ]

                    else
                        [ indexInList ]
            in
            return { model | selectedTrackIndexes = selection }

        Reply replies ->
            returnRepliesWithModel model replies

        ScrollToNowPlaying ->
            let
                -- The index identifier might be out-of-date,
                -- so we get the latest version.
                it =
                    model.nowPlaying
                        |> Maybe.map (Tuple.second >> .id)
                        |> Maybe.andThen
                            (\id ->
                                List.find
                                    (Tuple.second >> .id >> (==) id)
                                    model.collection.harvested
                            )
            in
            model.nowPlaying
                |> Maybe.map (Tuple.second >> .id)
                |> Maybe.andThen
                    (\id ->
                        List.find
                            (Tuple.second >> .id >> (==) id)
                            model.collection.harvested
                    )
                |> Maybe.map
                    (case model.scene of
                        List ->
                            UI.Tracks.Scene.List.scrollToNowPlaying model.collection.harvested
                    )
                |> Maybe.map
                    (\cmd ->
                        cmd
                            |> Return.commandWithModel model
                            |> Return.addReply (GoToPage UI.Page.Index)
                    )
                |> Maybe.withDefault (return model)

        SetEnabledSourceIds sourceIds ->
            reviseCollection identify
                { model | enabledSourceIds = sourceIds }

        SetNowPlaying maybeIdentifiedTrack ->
            -- TODO:
            -- Improve performance
            let
                mapFn =
                    case maybeIdentifiedTrack of
                        Just a ->
                            \( i, t ) -> Tuple.pair { i | isNowPlaying = isNowPlaying a ( i, t ) } t

                        Nothing ->
                            \( i, t ) -> Tuple.pair { i | isNowPlaying = False } t
            in
            reviseCollection
                (map <| List.map mapFn)
                { model | nowPlaying = maybeIdentifiedTrack }

        SortBy property ->
            let
                sortDir =
                    if model.sortBy /= property then
                        Asc

                    else if model.sortDirection == Asc then
                        Desc

                    else
                        Asc
            in
            { model | sortBy = property, sortDirection = sortDir }
                |> reviseCollection arrange
                |> addReply SaveEnclosedUserData

        ToggleHideDuplicates ->
            { model | hideDuplicates = not model.hideDuplicates }
                |> reviseCollection arrange
                |> addReply SaveSettings

        -----------------------------------------
        -- Collection
        -----------------------------------------
        -- # Add
        -- > Add tracks to the collection.
        --
        Add json ->
            reviseCollection
                (json
                    |> Json.decodeValue (Json.list Encoding.trackDecoder)
                    |> Result.withDefault []
                    |> add
                )
                model

        -- # Remove
        -- > Remove tracks from the collection.
        --
        RemoveByPaths json ->
            let
                decoder =
                    Json.map2
                        Tuple.pair
                        (Json.field "filePaths" <| Json.list Json.string)
                        (Json.field "sourceId" Json.string)

                ( paths, sourceId ) =
                    json
                        |> Json.decodeValue decoder
                        |> Result.withDefault ( [], missingId )
            in
            reviseCollection
                (Collection.removeByPaths sourceId paths)
                model

        RemoveBySourceId sourceId ->
            reviseCollection
                (Collection.removeBySourceId sourceId)
                model

        -----------------------------------------
        -- Favourites
        -----------------------------------------
        -- > Make a track a favourite, or remove it as a favourite
        ToggleFavourite index ->
            model.collection.harvested
                |> List.getAt index
                |> Maybe.map (toggleFavourite model)
                |> Maybe.withDefault (return model)

        -- > Filter collection by favourites only {toggle}
        ToggleFavouritesOnly ->
            { model | favouritesOnly = not model.favouritesOnly }
                |> reviseCollection harvest
                |> addReply SaveEnclosedUserData

        -----------------------------------------
        -- Groups
        -----------------------------------------
        DisableGrouping ->
            { model | grouping = Nothing }
                |> reviseCollection arrange
                |> addReply SaveEnclosedUserData

        GroupBy grouping ->
            { model | grouping = Just grouping }
                |> reviseCollection arrange
                |> addReply SaveEnclosedUserData

        -----------------------------------------
        -- Menus
        -----------------------------------------
        ShowTrackMenuWithSmallDelay a b ->
            ShowTrackMenu a b
                |> Task.doDelayed 250
                |> returnCommandWithModel model

        ShowTrackMenu trackIndex coordinates ->
            let
                selection =
                    if List.isEmpty model.selectedTrackIndexes then
                        [ trackIndex ]

                    else if List.member trackIndex model.selectedTrackIndexes == False then
                        [ trackIndex ]

                    else
                        model.selectedTrackIndexes
            in
            selection
                |> List.foldr
                    (\s acc ->
                        model.collection.harvested
                            |> List.getAt s
                            |> Maybe.map (List.addTo acc)
                            |> Maybe.withDefault acc
                    )
                    []
                |> ShowTracksContextMenu coordinates
                |> returnReplyWithModel
                    { model
                        | listDnD = DnD.initialModel
                        , selectedTrackIndexes = selection
                    }

        ShowViewMenu grouping mouseEvent ->
            grouping
                |> ShowTracksViewMenu (Coordinates.fromTuple mouseEvent.clientPos)
                |> returnReplyWithModel model

        -----------------------------------------
        -- Playlists
        -----------------------------------------
        DeselectPlaylist ->
            { model | selectedPlaylist = Nothing }
                |> reviseCollection arrange
                |> addReply SaveEnclosedUserData

        SelectPlaylist playlist ->
            { model | selectedPlaylist = Just playlist }
                |> reviseCollection arrange
                |> addReply SaveEnclosedUserData

        -----------------------------------------
        -- Scenes / List
        -----------------------------------------
        InfiniteListMsg infiniteList ->
            return { model | infiniteList = infiniteList }

        ListDragAndDropMsg subMsg ->
            let
                ( newDnD, replies ) =
                    DnD.update subMsg model.listDnD
            in
            if DnD.hasDropped newDnD then
                let
                    ( subject, target ) =
                        ( Maybe.withDefault 0 <| DnD.modelSubject newDnD
                        , Maybe.withDefault 0 <| DnD.modelTarget newDnD
                        )

                    moveFromTo =
                        { from = subject, to = target }

                    selectedPlaylist =
                        Maybe.map
                            (\p -> { p | tracks = List.move moveFromTo p.tracks })
                            model.selectedPlaylist
                in
                case selectedPlaylist of
                    Just playlist ->
                        { model | listDnD = newDnD, selectedPlaylist = Just playlist }
                            |> reviseCollection arrange
                            |> addReply (ReplacePlaylistInCollection playlist)

                    Nothing ->
                        returnRepliesWithModel
                            { model | listDnD = newDnD }
                            replies

            else
                returnRepliesWithModel
                    { model | listDnD = newDnD }
                    replies

        -----------------------------------------
        -- Search
        -----------------------------------------
        ClearSearch ->
            { model | searchResults = Nothing, searchTerm = Nothing }
                |> reviseCollection harvest
                |> addReply SaveEnclosedUserData

        Search ->
            case ( model.searchTerm, model.searchResults ) of
                ( Just term, _ ) ->
                    term
                        |> String.trim
                        |> Json.Encode.string
                        |> UI.Ports.giveBrain Alien.SearchTracks
                        |> Return.commandWithModel model

                ( Nothing, Just _ ) ->
                    reviseCollection harvest { model | searchResults = Nothing }

                ( Nothing, Nothing ) ->
                    return model

        SetSearchResults json ->
            case model.searchTerm of
                Just _ ->
                    json
                        |> Json.decodeValue (Json.list Json.string)
                        |> Result.withDefault []
                        |> (\results -> { model | searchResults = Just results })
                        |> reviseCollection harvest
                        |> addReply (ToggleLoadingScreen Off)

                Nothing ->
                    return model

        SetSearchTerm term ->
            addReplies
                [ SaveEnclosedUserData ]
                (case String.trim term of
                    "" ->
                        return { model | searchTerm = Nothing }

                    _ ->
                        return { model | searchTerm = Just term }
                )



-- 📣  ░░  PARCEL


makeParcel : Model -> Parcel
makeParcel model =
    ( { enabledSourceIds = model.enabledSourceIds
      , favourites = model.favourites
      , favouritesOnly = model.favouritesOnly
      , grouping = model.grouping
      , hideDuplicates = model.hideDuplicates
      , nowPlaying = model.nowPlaying
      , searchResults = model.searchResults
      , selectedPlaylist = model.selectedPlaylist
      , sortBy = model.sortBy
      , sortDirection = model.sortDirection
      }
    , model.collection
    )


resolveParcel : Model -> Parcel -> Return Model Msg Reply
resolveParcel model ( _, newCollection ) =
    let
        scrollObj =
            Json.Encode.object
                [ ( "scrollTop", Json.Encode.int 0 ) ]

        scrollEvent =
            Json.Encode.object
                [ ( "target", scrollObj ) ]

        collectionChanged =
            Collection.tracksChanged
                model.collection.untouched
                newCollection.untouched

        harvestChanged =
            if collectionChanged then
                True

            else
                Collection.harvestChanged
                    model.collection.harvested
                    newCollection.harvested

        modelWithNewCollection =
            { model
                | collection = newCollection
                , infiniteList =
                    if harvestChanged && model.scene == List then
                        InfiniteList.updateScroll scrollEvent model.infiniteList

                    else
                        model.infiniteList
                , selectedTrackIndexes =
                    if harvestChanged then
                        []

                    else
                        model.selectedTrackIndexes
            }
    in
    ( modelWithNewCollection
      ----------
      -- Command
      ----------
    , if harvestChanged then
        case model.scene of
            List ->
                UI.Tracks.Scene.List.scrollToTop

      else
        Cmd.none
      --------
      -- Reply
      --------
    , if collectionChanged then
        [ GenerateDirectoryPlaylists, ResetQueue ]

      else if harvestChanged then
        [ ResetQueue ]

      else
        []
    )


reviseCollection : (Parcel -> Parcel) -> Model -> Return Model Msg Reply
reviseCollection collector model =
    model
        |> makeParcel
        |> collector
        |> resolveParcel model



-- 📣  ░░  FAVOURITES


toggleFavourite : Model -> IdentifiedTrack -> Return Model Msg Reply
toggleFavourite model ( i, t ) =
    let
        newFavourites =
            Favourites.toggleInFavouritesList ( i, t ) model.favourites

        effect =
            if model.favouritesOnly then
                Collection.map (Favourites.toggleInTracksList t) >> harvest

            else
                Collection.map (Favourites.toggleInTracksList t)
    in
    { model | favourites = newFavourites }
        |> reviseCollection effect
        |> addReply SaveFavourites



-- 🗺


view : UI.Core.Model -> Html Msg
view core =
    chunk
        [ T.flex
        , T.flex_column
        , T.flex_grow_1
        ]
        [ lazy6
            navigation
            core.tracks.grouping
            core.tracks.favouritesOnly
            core.tracks.searchTerm
            core.tracks.selectedPlaylist
            core.page
            core.backdrop.bgColor

        --
        , if List.isEmpty core.tracks.collection.harvested then
            lazy4
                noTracksView
                core.sources.isProcessing
                (List.length core.sources.collection)
                (List.length core.tracks.collection.harvested)
                (List.length core.tracks.favourites)

          else
            case core.tracks.scene of
                List ->
                    UI.Tracks.Scene.List.view
                        { height = core.viewport.height
                        , isVisible = core.page == UI.Page.Index
                        }
                        core.tracks
        ]


navigation : Maybe Grouping -> Bool -> Maybe String -> Maybe Playlist -> Page -> Maybe Color -> Html Msg
navigation maybeGrouping favouritesOnly searchTerm selectedPlaylist page bgColor =
    let
        tabindex_ =
            case page of
                UI.Page.Index ->
                    0

                _ ->
                    -1
    in
    brick
        [ css navigationStyles ]
        [ T.flex, T.relative, T.z_4 ]
        [ -----------------------------------------
          -- Part 1
          -----------------------------------------
          brick
            [ css searchStyles ]
            [ T.flex
            , T.flex_grow_1
            , T.overflow_hidden
            ]
            [ -- Input
              --------
              slab
                Html.input
                [ css searchInputStyles
                , onBlur Search
                , onEnterKey Search
                , onInput SetSearchTerm
                , placeholder "Search"
                , tabindex tabindex_
                , value (Maybe.withDefault "" searchTerm)
                ]
                [ T.bg_transparent
                , T.bn
                , T.color_inherit
                , T.flex_grow_1
                , T.h_100
                , T.outline_0
                , T.pr2
                , T.w_100
                ]
                []

            -- Search icon
            --------------
            , brick
                [ css searchIconStyles ]
                [ T.absolute
                , T.bottom_0
                , T.flex
                , T.items_center
                , T.left_0
                , T.top_0
                , T.z_0
                ]
                [ Html.fromUnstyled (Icons.search 16 searchIconColoring) ]

            -- Actions
            ----------
            , brick
                [ css searchActionsStyles ]
                [ T.flex
                , T.items_center
                ]
                [ -- 1
                  case searchTerm of
                    Just _ ->
                        brick
                            [ css searchActionIconStyle
                            , onClick ClearSearch
                            , title "Clear search"
                            ]
                            [ T.pointer ]
                            [ Html.fromUnstyled (Icons.clear 16 searchIconColoring) ]

                    Nothing ->
                        nothing

                -- 2
                , brick
                    [ css searchActionIconStyle
                    , onClick ToggleFavouritesOnly
                    , title "Toggle favourites-only"
                    ]
                    [ T.pointer ]
                    [ case favouritesOnly of
                        True ->
                            Html.fromUnstyled (Icons.favorite 16 <| Color UI.Kit.colorKit.base08)

                        False ->
                            Html.fromUnstyled (Icons.favorite_border 16 searchIconColoring)
                    ]

                -- 3
                , brick
                    [ css searchActionIconStyle
                    , fromUnstyled (Mouse.onClick <| ShowViewMenu maybeGrouping)
                    , title "View settings"
                    ]
                    [ T.pointer ]
                    [ Html.fromUnstyled (Icons.more_vert 16 searchIconColoring) ]

                -- 4
                , case selectedPlaylist of
                    Just playlist ->
                        brick
                            [ css (selectedPlaylistStyles bgColor)
                            , onClick DeselectPlaylist
                            ]
                            [ T.br2
                            , T.f7
                            , T.fw7
                            , T.lh_solid
                            , T.pointer
                            , T.truncate
                            , T.white_90
                            ]
                            [ text playlist.name ]

                    Nothing ->
                        nothing
                ]
            ]
        , -----------------------------------------
          -- Part 2
          -----------------------------------------
          UI.Navigation.localWithTabindex
            tabindex_
            [ ( Icon Icons.waves
              , Label "Playlists" Hidden
              , NavigateToPage (UI.Page.Playlists UI.Playlists.Page.Index)
              )
            , ( Icon Icons.schedule
              , Label "Queue" Hidden
              , NavigateToPage (UI.Page.Queue UI.Queue.Page.Index)
              )
            , ( Icon Icons.equalizer
              , Label "Equalizer" Hidden
              , NavigateToPage UI.Page.Equalizer
              )
            ]
        ]


noTracksView : List String -> Int -> Int -> Int -> Html Msg
noTracksView isProcessing amountOfSources amountOfTracks amountOfFavourites =
    chunk
        [ T.flex, T.flex_grow_1 ]
        [ UI.Kit.centeredContent
            [ if List.length isProcessing > 0 then
                message "Processing Tracks"

              else if amountOfSources == 0 then
                chunk
                    [ T.flex, T.items_start, T.ph3 ]
                    [ inline
                        [ T.dib, T.mb2 ]
                        [ UI.Kit.buttonLink
                            "sources/new"
                            UI.Kit.Normal
                            (inline
                                []
                                [ UI.Kit.inlineIcon Icons.add
                                , text "Add some music"
                                ]
                            )
                        ]
                    , slab
                        Html.span
                        []
                        [ T.dib, T.w1 ]
                        []
                    , UI.Kit.buttonWithColor
                        UI.Kit.colorKit.base04
                        UI.Kit.Normal
                        (Reply [ InsertDemo ])
                        (inline
                            []
                            [ UI.Kit.inlineIcon Icons.music_note
                            , text "Insert demo"
                            ]
                        )
                    ]

              else if amountOfTracks == 0 then
                message "No tracks found"

              else
                message "No sources available"
            ]
        ]


message : String -> Html Msg
message m =
    chunk
        [ T.bb, T.bw1, T.f6, T.fw6, T.lh_title, T.pb1 ]
        [ text m ]



-- 🖼


navigationStyles : List Css.Style
navigationStyles =
    [ Css.boxShadow5 (Css.px 0) (Css.px 0) (Css.px 10) (Css.px 1) (Css.rgba 0 0 0 0.05)
    ]


searchStyles : List Css.Style
searchStyles =
    [ Css.borderBottom3 (Css.px 1) Css.solid (Color.toElmCssColor UI.Kit.colors.subtleBorder)
    , Css.borderRight3 (Css.px 1) Css.solid (Color.toElmCssColor UI.Kit.colors.subtleBorder)
    ]


searchActionsStyles : List Css.Style
searchActionsStyles =
    [ Css.fontSize (Css.px 0)
    , Css.lineHeight (Css.px 0)
    , Css.paddingRight (Css.px <| 13 - 6)
    ]


searchActionIconStyle : List Css.Style
searchActionIconStyle =
    [ Css.height (Css.px 15)
    , Css.marginRight (Css.px 6)
    ]


searchIconColoring : Coloring
searchIconColoring =
    Color (Color.rgb255 205 205 205)


searchIconStyles : List Css.Style
searchIconStyles =
    [ Css.marginTop (Css.px 1)
    , Css.paddingLeft (Css.px 13)
    ]


searchInputStyles : List Css.Style
searchInputStyles =
    [ Css.fontSize (Css.px 14)
    , Css.height (Css.pct 98)
    , Css.minWidth (Css.px 59)
    , Css.paddingLeft (Css.px <| 13 + 16 + 9)
    ]


selectedPlaylistStyles : Maybe Color -> List Css.Style
selectedPlaylistStyles bgColor =
    [ Css.backgroundColor (Color.toElmCssColor <| Maybe.withDefault UI.Kit.colorKit.base01 bgColor)
    , Css.fontSize (Css.px 11)
    , Css.marginRight (Css.px 6)
    , Css.padding3 (Css.px 5) (Css.px 5.5) (Css.px 4)
    , Css.Transitions.transition [ Css.Transitions.backgroundColor 450 ]
    ]
