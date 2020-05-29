module Main exposing (main)

import Browser
import Html exposing (..)
import Html.Attributes as HA
import Markdown.Option exposing (..)
import Markdown.Render exposing (MarkdownMsg(..), MarkdownOutput(..))


main : Program Flags Model Msg
main =
    Browser.element
        { view = view
        , update = update
        , init = init
        , subscriptions = subscriptions
        }


type alias Model =
    { sourceText : String
    }


type Msg
    = NoOp
    | MarkdownMsg Markdown.Render.MarkdownMsg


type alias Flags =
    {}


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { sourceText = svgText }, Cmd.none )


svgText =
    """
# This is a test

Some math:

$$
\\int_0^1 x^n dx = \\frac{1}{n+1}
$$

An svg figure:

@svg
<svg width="100" height="100">
  <circle cx="50" cy="50" r="40" stroke="green" stroke-width="1" fill="yellow" />
</svg>

Some Html entities:

&forall; (&bbA;:&caU;): &bbA; &to; &bbB;

"""


sourceText =
    """
>> &bbA;   &bbB; &bbC; &bbD; &bbE; &bbF;
&bbG; &bbH; &bbI; &bbJ; &bbK; &bbL; &bbM;
&bbN; &bbO; &bbP; &bbQ; &bbR; &bbS; &bbT;
&bbU; &bbV; &bbW; &bbX; &bbY; &bbZ;

>> &caA;   &caB; &caC; &caD; &caE; &caF;
&caG; &caH; &caI; &caJ; &caK; &caL; &caM;
&caN; &caO; &caP; &caQ; &caR; &caS; &caT;
&caU; &caV; &caW; &caX; &caY; &caZ;

>> &in; &notin; &sub; &nsub; &sup; &nsup;
&equiv; &nequiv; &not; &or; &and;
&forall; &exist; &nexist; &cup; &cap;

>> &rArr; &rarr; &lArr; &larr; &hArr; &harr;
&tilde; &excl; &middot; &amp; &def;

>> &oplus; &top; &bot; &vdash; &vDash; &down; &up;
&nor; &nand; &dagger; &boolzero; &boolone; &empty;



"""


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        MarkdownMsg _ ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    Html.div [ HA.style "margin" "50px", HA.style "width" "500px" ]
        [ Markdown.Render.toHtml ExtendedMath model.sourceText
            |> Html.map MarkdownMsg
        ]
