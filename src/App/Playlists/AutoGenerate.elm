module Playlists.AutoGenerate exposing (..)

import Dict
import List.Extra as List
import Playlists.Types exposing (..)
import Sources.Types exposing (Source)
import Tracks.Types exposing (Track)


-- 🚜


autoGenerate : List Source -> List Track -> List Playlist
autoGenerate sources tracks =
    let
        relevantSources =
            List.filter .directoryPlaylists sources

        relevantSourceIds =
            List.map .id relevantSources

        playlistNames =
            tracks
                |> List.filter (\t -> List.member t.sourceId relevantSourceIds)
                |> List.foldr (tracksReducer relevantSources) []
    in
        List.map
            (\n ->
                { autoGenerated = True
                , name = n
                , tracks = []
                }
            )
            playlistNames



--


tracksReducer : List Source -> Track -> List String -> List String
tracksReducer relevantSources track acc =
    let
        prefix =
            deducePathPrefix relevantSources track

        path =
            String.dropLeft (String.length prefix) track.path

        name =
            path
                |> String.split "/"
                |> List.head
                |> Maybe.withDefault ""
    in
        if String.contains "/" path == False then
            acc
        else if List.member name acc == False then
            name :: acc
        else
            acc


deducePathPrefix : List Source -> Track -> String
deducePathPrefix relevantSources track =
    if String.startsWith "/" track.path then
        relevantSources
            |> List.find (\s -> s.id == track.sourceId)
            |> Maybe.map .data
            |> Maybe.andThen (Dict.get "directoryPath")
            |> Maybe.map
                (\s ->
                    if not (String.startsWith "/" s) then
                        "/" ++ s
                    else
                        s
                )
            |> Maybe.map
                (\s ->
                    if not (String.endsWith "/" s) then
                        s ++ "/"
                    else
                        s
                )
            |> Maybe.withDefault "/"
    else
        ""
