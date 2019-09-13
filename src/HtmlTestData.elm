module HtmlTestData exposing (..)

import Parse
import Markdown.Option exposing(..)
import Tree exposing (Tree)
import TestHelpers

import TestTypes exposing(..)

commonMark : List TestDatum
commonMark = [

    {
      markdown =  " ### foo\n  ## foo\n   # foo\n"
    , html = "<h3>foo</h3>\n<h2>foo</h2>\n<h1>foo</h1>\n"
    , example = 38
    , startLine = 841
    , endLine = 849
    , section = "ATX headings"
    }

  ]


basic : List SmallTestDatum
basic = [

    {
      markdown = "",
      html = "",
      example = 0,
      section = "Empty"
      }

   , {
        markdown = "plain text",
        html = "",
        example = 1,
        section = "Text"
      }

   , {
        markdown = "$a^2 + b^2 + c^2$",
        html = "",
        example = 2,
        section = "Inline math"
      }

  , {
        markdown = "$$a^2 + b^2 + c^2$$",
        html = "",
        example = 3,
        section = "Inline math"
      }

  , {
     markdown = "# foo\n",
     html = "<h3>foo</h3>\n",
     example = 4,
     section = "ATX headings"
     }
  ]

