module Markdown.Render exposing
    ( MarkdownMsg(..), MarkdownOutput(..), DocumentParts
    , withOptions, withOptionsFromAST, withSimpleOptions
    , content, title, toc
    , renderHtml, toHtml, numberOfMathElements
    )

{-|


## Simple Applications

When there is no interaction between the Markdown text and and an
on-the-fly editor, use the `withSimpleOptions` function:

    withSimpleOptions :
        MarkdownOption
        -> OutputOption
        -> String
        -> MarkdownOutput

For example:

    withSimpleOptions Extended Basic "This is *italic text.*"
        |> content
        |> Html.map MarkdownMsg

where one has

    import Markdown.Render exposing(withSimpleOptions, MarkdownMsg(..))
    import Markdown.Options expsosing(..)

    type Msg = MarkdownMsg MarkdownMsg | ...


## Editor interaction

Use the `withOptions` and `withOptionsFromAST` functions if you need
more control over the editing process (see the `./Editor` folder
for examples).

The function `parse` yields a syntax tree (AST: abstract syntax tree). The functions `renderHtml`,
`renderHtmlWithTOC`, and `renderHtmlWithExternaTOC` render the
AST in various forms, as described below.

This library


## Optimizations

The idea of the optimizations used in `app-demo-optimized`
(see the repo)
is to parse the document text when the
document is first opened. The resulting parse
tree is stored as
`model.lastAst`. Each block in the AST carries
a label `(version, id): (Int, Int)`, where
the `id` is unique to each block.
Each time the text changes, a new AST is computed
with an incremented version number. The
function `Diff.mergeWith equals` is applied to
the old and new ASTs
to compute an updated AST. The updated AST
is identical to the new AST except for the id's.
The id of a node in the updated AST is
the same as in the old AST if and only if the type, level,
and content of the node has not changed.
This information is used to signal MathJax not
to re-render mathematical text that is unchanged.

To see where these optimizations are applied,
look for the places in `app-demo-optimized/Main.elm`
where functions in the modules
`ParseWithId` and `Markdown.ElmWithId` are called.


## Types

@docs MarkdownMsg, MarkdownOutput, DocumentParts


## Rendering

@docs withOptions, withOptionsFromAST, withSimpleOptions


## Extracting content from a MarkdownOutput value

@docs content, title, toc


## Utility

@docs renderHtml, toHtml, numberOfMathElements

-}

import BlockType exposing (BalancedType(..), BlockType(..), Language(..), Level, MarkdownType(..))
import Html exposing (Html)
import Html.Attributes as HA exposing (style)
import Html.Events as HE
import Html.Keyed as Keyed
import Json.Encode
import MDInline exposing (MDInline(..))
import Markdown.Option exposing (MarkdownOption(..), OutputOption(..))
import Markdown.Parse as Parse
    exposing
        ( BlockContent(..)
        , Id
        , MDBlock(..)
        , MDBlockWithId(..)
        , idOfBlock
        , project
        , projectedStringOfBlockContent
        , stringFromId
        )
import Parser
import SyntaxHighlight exposing (monokai, toBlockHtml, useTheme)
import Tree exposing (Tree)


{-| Use `Html MarkdownMsg` so that user clicks on elements in the rendered text can be detected.
-}
type MarkdownMsg
    = IDClicked String


{-| The kinds of Markdown output
-}
type MarkdownOutput
    = Simple (Html MarkdownMsg)
    | Composite DocumentParts


{-| The type of a composite document
-}
type alias DocumentParts =
    { title : Html MarkdownMsg
    , toc : Html MarkdownMsg
    , document : Html MarkdownMsg
    }


{-| Extract the title from a MarkdownOutput value
-}
title : MarkdownOutput -> Html MarkdownMsg
title markdownOutput =
    case markdownOutput of
        Simple _ ->
            Html.span [] []

        Composite docParts ->
            docParts.title


{-| Extract the table of contents from a MarkdownOutput value
-}
toc : MarkdownOutput -> Html MarkdownMsg
toc markdownOutput =
    case markdownOutput of
        Simple _ ->
            Html.span [] []

        Composite docParts ->
            docParts.toc


{-| Extract the content from a MarkdownOutput value
-}
content : MarkdownOutput -> Html MarkdownMsg
content markdownOutput =
    case markdownOutput of
        Simple html ->
            html

        Composite docParts ->
            docParts.document


{-| Render source text with simplified opptions
-}
withSimpleOptions : MarkdownOption -> OutputOption -> String -> MarkdownOutput
withSimpleOptions markdownOption outputOption content_ =
    withOptions markdownOption outputOption ( 0, 0 ) 0 content_


{-| Render source text
-}
withOptions : MarkdownOption -> OutputOption -> Id -> Int -> String -> MarkdownOutput
withOptions markdownOption outputOption selectedId version content_ =
    case
        outputOption
    of
        Basic ->
            toHtml selectedId version markdownOption content_ |> Simple

        InternalTOC title_ ->
            renderHtmlWithTOC selectedId title_ (Parse.toMDBlockTree version markdownOption content_)
                |> Simple

        ExternalTOC title_ ->
            renderHtmlWithExternalTOC selectedId title_ (Parse.toMDBlockTree version markdownOption content_)
                |> Composite


{-| Render from an AST
-}
withOptionsFromAST : MarkdownOption -> OutputOption -> Id -> Tree MDBlockWithId -> MarkdownOutput
withOptionsFromAST markdownOption outputOption selectedId ast =
    case
        outputOption
    of
        Basic ->
            renderHtml selectedId ast
                |> Simple

        InternalTOC title_ ->
            renderHtmlWithTOC selectedId title_ ast
                |> Simple

        ExternalTOC title_ ->
            renderHtmlWithExternalTOC selectedId title_ ast
                |> Composite



--- INTERNAL


parserOfLanguage : Language -> (String -> Result (List Parser.DeadEnd) SyntaxHighlight.HCode)
parserOfLanguage lang_ =
    case lang_ of
        ElmLang ->
            SyntaxHighlight.elm

        CssLang ->
            SyntaxHighlight.css

        JavascriptLang ->
            SyntaxHighlight.javascript

        JsonLang ->
            SyntaxHighlight.json

        PythonLang ->
            SyntaxHighlight.python

        SqlLang ->
            SyntaxHighlight.sql

        XmlLang ->
            SyntaxHighlight.xml


typeOfMDBlock : MDBlock -> BlockType
typeOfMDBlock (MDBlock bt _ _) =
    bt


isHeading : MDBlock -> Bool
isHeading block =
    case typeOfMDBlock block of
        MarkdownBlock (Heading _) ->
            True

        _ ->
            False


typeOfMDBlockWithId : MDBlockWithId -> BlockType
typeOfMDBlockWithId (MDBlockWithId _ bt _ _) =
    bt


isHeadingWithId : MDBlockWithId -> Bool
isHeadingWithId block =
    case typeOfMDBlockWithId block of
        MarkdownBlock (Heading _) ->
            True

        _ ->
            False


isMathWithId : MDBlockWithId -> Bool
isMathWithId block =
    case typeOfMDBlockWithId block of
        BalancedBlock DisplayMath ->
            True

        _ ->
            False


id0 =
    ( -1, -1 )


{-| Parse the input and render it to Html, e.g.,

toHtml ExtendedMath "Pythagoras said: $a^2 + b^2 c^2$."

-}
toHtml : Id -> Int -> MarkdownOption -> String -> Html MarkdownMsg
toHtml selectedId version option str =
    str
        |> Parse.toMDBlockTree version option
        |> renderHtml selectedId


masterId =
    HA.id "__RENDERED_TEXT__"


{-| Render a parse tree to Html.
-}
renderHtml : Id -> Tree MDBlockWithId -> Html MarkdownMsg
renderHtml selectedId blockTreeWithId =
    blockTreeWithId
        |> Tree.children
        |> List.map (mmBlockTreeToHtml selectedId)
        |> (\x -> Html.div [ masterId ] x)


toHtmlWithTOC : Id -> Int -> MarkdownOption -> String -> String -> Html MarkdownMsg
toHtmlWithTOC selectedId version option heading str =
    let
        ast : Tree MDBlockWithId
        ast =
            Parse.toMDBlockTree version option str

        toc_ : Html MarkdownMsg
        toc_ =
            tableOfContentsAsHtml heading (Tree.map project ast)

        bodyAST : List (Tree MDBlockWithId)
        bodyAST =
            ast |> Tree.children

        headOfBodyAST =
            List.head bodyAST |> Maybe.map (Tree.map project)

        html =
            bodyAST |> List.map (mmBlockTreeToHtml selectedId)

        title_ =
            List.head html |> Maybe.withDefault (Html.div [] [])

        body =
            List.drop 1 html

        separator =
            Html.hr [ HA.style "padding-bottom" "2px", HA.style "background-color" "#aaa", HA.style "border-width" "0" ] []

        spacing =
            Html.div [ HA.style "padding-bottom" "40px" ] []
    in
    case Maybe.map (isHeading << Tree.label) headOfBodyAST of
        Just True ->
            Html.div [ masterId ] (title_ :: separator :: toc_ :: separator :: spacing :: body)

        _ ->
            Html.div [ masterId ] (separator :: toc_ :: separator :: spacing :: title_ :: body)


{-| Like `renderHtml`, but constructs a table of contents.
-}
renderHtmlWithTOC : Id -> String -> Tree MDBlockWithId -> Html MarkdownMsg
renderHtmlWithTOC selectedId heading ast =
    let
        toc_ : Html MarkdownMsg
        toc_ =
            tableOfContentsAsHtml heading (Tree.map project ast)

        bodyAST : List (Tree MDBlockWithId)
        bodyAST =
            ast |> Tree.children

        headOfBodyAST =
            List.head bodyAST |> Maybe.map (Tree.map project)

        html =
            bodyAST |> List.map (mmBlockTreeToHtml selectedId)

        title_ =
            List.head html |> Maybe.withDefault (Html.div [] [])

        body =
            List.drop 1 html

        separator =
            Html.hr [ HA.style "padding-bottom" "2px", HA.style "background-color" "#aaa", HA.style "border-width" "0" ] []

        spacing =
            Html.div [ HA.style "padding-bottom" "40px" ] []
    in
    case Maybe.map (isHeading << Tree.label) headOfBodyAST of
        Just True ->
            Html.div [ masterId ] (title_ :: separator :: toc_ :: separator :: spacing :: body)

        _ ->
            Html.div [ masterId ] (separator :: toc_ :: separator :: spacing :: title_ :: body)


{-| Like `renderHtmlWithTOC`, but transforms a parser tree into a record,
with fields for the document title, the table of contents, and the body
of the document.
-}
renderHtmlWithExternalTOC : Id -> String -> Tree MDBlockWithId -> DocumentParts
renderHtmlWithExternalTOC selectedId heading ast =
    let
        toc_ : Html MarkdownMsg
        toc_ =
            tableOfContentsAsHtml heading (Tree.map project ast)

        bodyAST =
            ast |> Tree.children

        html =
            bodyAST |> List.map (mmBlockTreeToHtml selectedId)

        title_ =
            List.head html |> Maybe.withDefault (Html.div [] [])

        body =
            List.drop 1 html

        separator =
            Html.hr [ HA.style "padding-bottom" "2px", HA.style "background-color" "#aaa", HA.style "border-width" "0" ] []

        spacing =
            Html.div [ HA.style "padding-bottom" "40px" ] []
    in
    { title = Html.div [] [ title_ ]
    , toc = Html.div [] [ toc_ ]
    , document = Html.div [ HA.id "__RENDERED_TEXT__" ] body
    }


highlightColor =
    "#8d9ffe"


makeKeyedNodeBody : Id -> Id -> Int -> MDInline -> ( String, Html MarkdownMsg )
makeKeyedNodeBody selectedId id level mDInline =
    ( stringFromId id, renderToHtmlMsg selectedId id level mDInline )


selectedStyle_ : Id -> Id -> Html.Attribute MarkdownMsg
selectedStyle_ targetId currentId =
    case targetId == currentId of
        True ->
            HA.style "background-color" "#8d9ffe"

        False ->
            HA.style "background-color" "none"


selectedStyle : Id -> Id -> List (Html.Attribute MarkdownMsg)
selectedStyle targetId currentId =
    case targetId == currentId of
        True ->
            [ HA.style "background-color" highlightColor ]

        False ->
            []


mmBlockTreeToHtml : Id -> Tree MDBlockWithId -> Html MarkdownMsg
mmBlockTreeToHtml selectedId tree =
    if Tree.children tree == [] then
        -- Render leaf blocks
        let
            (MDBlockWithId id bt lev content_) =
                Tree.label tree
        in
        case bt of
            BalancedBlock DisplayMath ->
                Keyed.node "spanXXX"
                    (selectedStyle selectedId id ++ [ HE.onClick (IDClicked (stringFromId id)) ])
                    [ ( stringFromId id, renderBlock selectedId id (MDBlock bt lev content_) ) ]

            _ ->
                Keyed.node "span" (selectedStyle selectedId id ++ [ HE.onClick (IDClicked (stringFromId id)) ]) [ ( stringFromId id, renderBlock selectedId id (MDBlock bt lev content_) ) ]

    else
        case Tree.label tree of
            MDBlockWithId id (MarkdownBlock TableRow) _ _ ->
                Html.tr [ HA.class "mm-table-row", selectedStyle_ selectedId id ]
                    (List.map (mmBlockTreeToHtml selectedId) (Tree.children tree))

            MDBlockWithId id (MarkdownBlock Table) _ _ ->
                Keyed.node "table"
                    [ HA.class "mm-table", HA.id (stringFromId id), HE.onClick (IDClicked (stringFromId id)), selectedStyle_ selectedId id ]
                    [ ( stringFromId id, Html.div [] (List.map (mmBlockTreeToHtml selectedId) (Tree.children tree)) ) ]

            MDBlockWithId id (MarkdownBlock Plain) _ _ ->
                Html.div [ HA.class "mm-plain", HA.id (stringFromId id), HE.onClick (IDClicked (stringFromId id)), selectedStyle_ selectedId id ] (List.map (mmBlockTreeToHtml selectedId) (Tree.children tree))

            MDBlockWithId id (MarkdownBlock _) _ _ ->
                Keyed.node "div"
                    [ selectedStyle_ selectedId id ]
                    [ ( stringFromId id
                      , Html.div [ HA.id (stringFromId id), HE.onClick (IDClicked (stringFromId id)) ]
                            [ renderBlock selectedId id (project (Tree.label tree))
                            , Html.div [ idAttr id ] (List.map (mmBlockTreeToHtml selectedId) (Tree.children tree))
                            ]
                      )
                    ]

            MDBlockWithId id (BalancedBlock DisplayMath) level content_ ->
                Keyed.node "div"
                    [ HA.id (stringFromId id), HE.onClick (IDClicked (stringFromId id)), selectedStyle_ selectedId id ]
                    [ ( stringFromId id, displayMathText (projectedStringOfBlockContent content_) ) ]

            MDBlockWithId id (BalancedBlock Verbatim) _ _ ->
                Keyed.node "pre" [ HA.id (stringFromId id), HE.onClick (IDClicked (stringFromId id)), selectedStyle_ selectedId id ] [ ( stringFromId id, Html.text "OUF: Verbatim!" ) ]

            MDBlockWithId id (BalancedBlock (DisplayCode lang)) _ _ ->
                Html.div [ HA.id (stringFromId id), HE.onClick (IDClicked (stringFromId id)), selectedStyle_ selectedId id ] [ Html.text "OUF: Code!" ]


tableOfContentsAsBlocks : Tree MDBlock -> List MDBlock
tableOfContentsAsBlocks blockTree =
    blockTree
        |> Tree.flatten
        |> List.filter isHeading


{-| Count the number of display math element blocks in the parse tree
-}
numberOfMathElements : Tree MDBlockWithId -> Int
numberOfMathElements blockTree =
    blockTree
        |> Tree.flatten
        |> List.filter isMathWithId
        |> List.length


tableOfContentsAsHtml : String -> Tree MDBlock -> Html MarkdownMsg
tableOfContentsAsHtml heading blockTree =
    blockTree
        |> tableOfContentsAsBlocks
        |> renderTableOfContents heading


renderTableOfContents : String -> List MDBlock -> Html MarkdownMsg
renderTableOfContents heading blockList =
    let
        contentHeading =
            MDBlock (MarkdownBlock (Heading 1)) 1 (M (Paragraph [ Line [ OrdinaryText heading ] ]))
    in
    blockList
        |> List.drop 1
        |> (\x -> contentHeading :: x)
        |> List.map renderHeadingForTOC
        |> (\x -> Html.div tocStyle x)


tocStyle =
    [ HA.style "font-size" "x-small"
    , HA.style "margin-left" "15px"
    , HA.style "color" "#555"
    , HA.id "toc"
    ]


renderHeadingForTOC : MDBlock -> Html MarkdownMsg
renderHeadingForTOC heading =
    case heading of
        MDBlock (MarkdownBlock (Heading k)) level blockContent ->
            renderTOCHeading ( 0, 0 ) id0 k level blockContent

        _ ->
            Html.span [] []


idAttr : Id -> Html.Attribute MarkdownMsg
idAttr id =
    HA.id (stringFromId id)


idAttrWithLabel : Id -> String -> Html.Attribute MarkdownMsg
idAttrWithLabel id label =
    HA.id (stringFromId id ++ label)


renderBlock : Id -> Id -> MDBlock -> Html MarkdownMsg
renderBlock selectedId id block =
    case block of
        MDBlock (MarkdownBlock Root) _ _ ->
            Html.div [ idAttr id, selectedStyle_ selectedId id ] []

        MDBlock (MarkdownBlock Plain) level blockContent ->
            renderBlockContent selectedId id level blockContent

        MDBlock (MarkdownBlock Blank) level blockContent ->
            renderBlockContent selectedId id level blockContent

        MDBlock (MarkdownBlock (Heading k)) level blockContent ->
            renderHeading selectedId id k level blockContent

        MDBlock (MarkdownBlock Quotation) level blockContent ->
            renderQuotation selectedId id level blockContent

        MDBlock (MarkdownBlock Poetry) level blockContent ->
            renderPoetry selectedId id level blockContent

        MDBlock (MarkdownBlock UListItem) level blockContent ->
            renderUListItem selectedId id level blockContent

        MDBlock (MarkdownBlock (OListItem index)) level blockContent ->
            renderOListItem selectedId id index level blockContent

        MDBlock (MarkdownBlock HorizontalRule) level blockContent ->
            Html.hr [ idAttr id, HA.class "mm-thematic-break", selectedStyle_ selectedId id ] []

        MDBlock (MarkdownBlock BlockType.Image) level blockContent ->
            renderBlockContent selectedId id level blockContent

        MDBlock (BalancedBlock DisplayMath) level blockContent ->
            case blockContent of
                T str ->
                    Html.div [ idAttr id, marginOfLevel level, selectedStyle_ selectedId id ] [ displayMathText str ]

                _ ->
                    displayMathText ""

        MDBlock (BalancedBlock Verbatim) level blockContent ->
            case blockContent of
                T str ->
                    Html.pre [ idAttr id, marginOfLevel level, selectedStyle_ selectedId id ] [ Html.text str ]

                _ ->
                    displayMathText ""

        MDBlock (BalancedBlock (DisplayCode lang)) level blockContent ->
            case blockContent of
                T str ->
                    Html.div [ blockLevelClass (level - 1) ]
                        [ useTheme monokai
                        , parserOfLanguage lang (String.trimLeft <| BlockType.deleteLangPrefix lang str)
                            |> Result.map (toBlockHtml (Just 1))
                            |> Result.withDefault
                                (Html.pre [] [ Html.code [] [ Html.text str ] ])
                        ]

                _ ->
                    displayMathText ""

        MDBlock (MarkdownBlock TableCell) level blockContent ->
            Html.td [ HA.class "mm-table-cell" ] [ renderBlockContent selectedId id level blockContent ]

        MDBlock (MarkdownBlock TableRow) level blockContent ->
            Html.tr [ HA.class "mm-table-row" ] [ renderBlockContent selectedId id level blockContent ]

        MDBlock (MarkdownBlock Table) level blockContent ->
            Html.table [ HA.class "mm-table", marginOfLevel level ] [ renderBlockContent selectedId id level blockContent ]


marginOfLevel level =
    HA.style "margin-left" (String.fromInt (0 * level) ++ "px")


blockLevelClass k =
    HA.class <| "mm-block-" ++ String.fromInt k


unWrapParagraph : MDInline -> List MDInline
unWrapParagraph mmInline =
    case mmInline of
        Paragraph element ->
            element

        _ ->
            []


renderUListItem : Id -> Id -> Level -> BlockContent -> Html MarkdownMsg
renderUListItem selectedId id level blockContent =
    let
        label =
            case level of
                1 ->
                    "• "

                2 ->
                    "◊ "

                3 ->
                    "† "

                4 ->
                    "‡ "

                _ ->
                    "N. "
    in
    Html.li
        [ HA.class "mm-ulist-item"
        , blockLevelClass (level - 1)
        , idAttr id
        , selectedStyle_ selectedId id
        ]
        [ renderBlockContent selectedId id level <| prependToParagraph (OrdinaryText label) blockContent ]


prependToParagraph : MDInline -> BlockContent -> BlockContent
prependToParagraph head tail =
    case tail of
        T _ ->
            tail

        M mmInLine ->
            case mmInLine of
                Paragraph lst ->
                    M (Paragraph (head :: lst))

                _ ->
                    tail


renderOListItem : Id -> Id -> Int -> Level -> BlockContent -> Html MarkdownMsg
renderOListItem selectedId id index level blockContent =
    let
        label =
            case level of
                1 ->
                    String.fromInt index ++ ". "

                2 ->
                    alphabet index ++ ". "

                3 ->
                    romanNumeral index ++ ". "

                4 ->
                    String.fromInt index ++ ". "

                _ ->
                    "N. "
    in
    Html.li
        [ HA.class "mm-olist-item"
        , blockLevelClass (level - 1)
        , idAttr id
        , selectedStyle_ selectedId id
        ]
        [ renderBlockContent selectedId id level (prependToParagraph (OrdinaryText label) blockContent) ]


renderHeading : Id -> Id -> Int -> Level -> BlockContent -> Html MarkdownMsg
renderHeading selectedId id k level blockContent =
    let
        name =
            nameFromBlockContent blockContent
    in
    case k of
        1 ->
            Html.h1 [ HA.id name, HA.class "mm-h1", selectedStyle_ selectedId id ] [ renderBlockContent selectedId id level blockContent ]

        2 ->
            Html.h2 [ HA.id name, HA.class "mm-h2", selectedStyle_ selectedId id ] [ renderBlockContent selectedId id level blockContent ]

        3 ->
            Html.h3 [ HA.id name, HA.class "mm-h3", selectedStyle_ selectedId id ] [ renderBlockContent selectedId id level blockContent ]

        4 ->
            Html.h4 [ HA.id name, HA.class "mm-h4", selectedStyle_ selectedId id ] [ renderBlockContent selectedId id level blockContent ]

        _ ->
            Html.h5 [ HA.id name, HA.class "mm-h5", selectedStyle_ selectedId id ] [ renderBlockContent selectedId id level blockContent ]


renderTOCHeading : Id -> Id -> Int -> Level -> BlockContent -> Html MarkdownMsg
renderTOCHeading selectedId id k level blockContent =
    let
        name =
            "#" ++ nameFromBlockContent blockContent
    in
    case k of
        1 ->
            Html.a [ HA.href name, HA.style "font-size" "13pt" ] [ renderBlockContent selectedId id level blockContent ]

        2 ->
            Html.a [ HA.href name, HA.class "toc-level-0", HA.style "display" "block" ] [ renderBlockContent selectedId id level blockContent ]

        3 ->
            Html.a [ HA.href name, HA.class "toc-level-1", HA.style "display" "block" ] [ renderBlockContent selectedId id level blockContent ]

        4 ->
            Html.a [ HA.href name, HA.class "toc-level-2", HA.style "display" "block" ] [ renderBlockContent selectedId id level blockContent ]

        _ ->
            Html.a [ HA.href name, HA.class "toc-level-3", HA.style "display" "block" ] [ renderBlockContent selectedId id level blockContent ]


renderQuotation : Id -> Id -> Level -> BlockContent -> Html MarkdownMsg
renderQuotation selectedId id level blockContent =
    Html.div
        [ HA.class "mm-quotation", blockLevelClass level, selectedStyle_ selectedId id ]
        [ renderBlockContent selectedId id level blockContent ]


renderPoetry : Id -> Id -> Level -> BlockContent -> Html MarkdownMsg
renderPoetry selectedId id level blockContent =
    Html.div
        [ HA.class "mm-poetry", marginOfLevel level, selectedStyle_ selectedId id ]
        [ renderBlockContent selectedId id level blockContent ]


renderBlockContent : Id -> Id -> Level -> BlockContent -> Html MarkdownMsg
renderBlockContent selectedId id level blockContent =
    case blockContent of
        M mmInline ->
            renderToHtmlMsg selectedId id level mmInline

        T str ->
            Html.span [ idAttr id, blockLevelClass (level - 1), selectedStyle_ selectedId id ] [ Html.text str ]


nameFromBlockContent : BlockContent -> String
nameFromBlockContent blockContent =
    case blockContent of
        M (Paragraph [ Line [ OrdinaryText str ] ]) ->
            String.trim str

        _ ->
            ""


renderToHtmlMsg : Id -> Id -> Level -> MDInline -> Html MarkdownMsg
renderToHtmlMsg selectedId id level mmInline =
    case mmInline of
        OrdinaryText str ->
            Html.span [ idAttr id, HA.class "ordinary", marginOfLevel level ] [ Html.text str ]

        ItalicText str ->
            Html.em [] [ Html.text str ]

        BoldText str ->
            Html.strong [] [ Html.text str ]

        Code str ->
            Html.code [ idAttr id ] [ Html.text str ]

        InlineMath str ->
            inlineMathText id str

        StrikeThroughText str ->
            strikethrough str

        BracketedText str ->
            Html.span [ HA.class "bracketed" ] [ Html.text <| "[" ++ str ++ "]" ]

        Link url label ->
            Html.a [ HA.href url ] [ Html.text (label ++ " ") ]

        MDInline.Image label_ url ->
            let
                labelParts =
                    List.take 2 (String.split "::" label_)

                ( label, class ) =
                    case ( List.head labelParts, List.head (List.drop 1 labelParts) ) of
                        ( Just label__, Just class__ ) ->
                            ( label__, "mm-image-" ++ class__ )

                        ( Just label__, Nothing ) ->
                            ( label__, "mm-image" )

                        ( _, _ ) ->
                            ( "image", "mm-image" )
            in
            Html.img [ idAttr id, HA.src url, HA.class class ] [ Html.text label ]

        Line arg ->
            let
                joined =
                    joinLine selectedId id level arg
            in
            if List.length joined == 1 then
                List.head joined |> Maybe.withDefault (Html.span [] [ Html.text "" ])

            else
                Html.span [ HA.class "line" ] joined

        Paragraph arg ->
            let
                mapper : MDInline -> ( String, Html MarkdownMsg )
                mapper =
                    \m -> ( stringFromId id, renderToHtmlMsg selectedId id level m )
            in
            Keyed.node "p"
                [ idAttr id, selectedStyle_ selectedId id, HA.class "mm-paragraph", blockLevelClass (level - 1) ]
                (List.map mapper arg)

        Stanza arg ->
            renderStanza id arg

        Error arg ->
            Html.p [] (List.map (renderToHtmlMsg selectedId id level) arg)


renderStanza : Id -> String -> Html MarkdownMsg
renderStanza id arg =
    let
        lines =
            String.split "\n" arg

        poetryLine line =
            Html.div [] [ Html.text line ]
    in
    Html.div [ idAttr id, HA.class "mm-poetry" ] (List.map poetryLine lines)


joinLine : Id -> Id -> Level -> List MDInline -> List (Html MarkdownMsg)
joinLine selectedId id level items =
    let
        folder : MDInline -> ( List String, List (Html MarkdownMsg) ) -> ( List String, List (Html MarkdownMsg) )
        folder item ( accString, accElement ) =
            case item of
                OrdinaryText str ->
                    ( str :: accString, accElement )

                _ ->
                    if accString /= [] then
                        let
                            content_ =
                                String.join "" accString

                            span =
                                Html.span [ HA.class "innerJoin" ] [ Html.text content_ ]
                        in
                        ( [], renderToHtmlMsg selectedId id level item :: span :: accElement )

                    else
                        ( [], renderToHtmlMsg selectedId id level item :: accElement )

        flush : ( List String, List (Html MarkdownMsg) ) -> List (Html MarkdownMsg)
        flush ( accString, accElement ) =
            if accString /= [] then
                let
                    content_ =
                        String.join "" accString

                    span =
                        Html.span [] [ Html.text content_ ]
                in
                span :: accElement

            else
                accElement
    in
    List.foldl folder ( [], [] ) items
        |> flush
        |> List.reverse


isPunctuation : String -> Bool
isPunctuation str =
    List.member str [ ".", ",", ";", ":", "?", "!" ]


strikethrough : String -> Html MarkdownMsg
strikethrough str =
    Html.span [ HA.class "mm-strike-through" ] [ Html.text str ]



-- MATH --


mathText : String -> Html MarkdownMsg
mathText content_ =
    Html.node "math-text"
        [ HA.class "mm-math", HA.property "content_" (Json.Encode.string content_) ]
        []


inlineMathText : Id -> String -> Html MarkdownMsg
inlineMathText id str =
    Keyed.node "span" [ idAttrWithLabel id "m" ] [ ( stringFromId id ++ "m", mathText <| "$ " ++ String.trim str ++ " $ " ) ]


displayMathText : String -> Html MarkdownMsg
displayMathText str =
    let
        str2 =
            String.trim str
    in
    mathText <| "$$\n" ++ str2 ++ "\n$$"



-- HELPERS --


alphabet : Int -> String
alphabet k =
    let
        alpha =
            [ "a"
            , "b"
            , "c"
            , "d"
            , "e"
            , "f"
            , "g"
            , "h"
            , "i"
            , "j"
            , "k"
            , "l"
            , "m"
            , "n"
            , "o"
            , "p"
            , "q"
            , "r"
            , "s"
            , "t"
            , "u"
            , "v"
            , "w"
            , "x"
            , "y"
            , "z"
            ]
    in
    List.drop (k - 1) alpha |> List.head |> Maybe.withDefault "zz"


romanNumeral : Int -> String
romanNumeral k =
    let
        alpha =
            [ "i"
            , "ii"
            , "iii"
            , "iv"
            , "v"
            , "vi"
            , "vii"
            , "viii"
            , "ix"
            , "x"
            , "xi"
            , "xii"
            , "xiii"
            , "xiv"
            , "xv"
            , "xvi"
            , "xvii"
            , "xviii"
            , "xix"
            , "xx"
            , "xxi"
            , "xxii"
            , "xxiii"
            , "xiv"
            , "xv"
            , "xvi"
            ]
    in
    List.drop (k - 1) alpha |> List.head |> Maybe.withDefault "zz"
