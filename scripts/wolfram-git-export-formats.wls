#!/usr/bin/env wolframscript
(* ::Package:: *)
(* wolfram-git-export-formats.wls: Export Wolfram notebooks to companion formats (markdown, etc.) with output cells discarded *)

Quiet[
  Module[{
    args = Rest[$ScriptCommandLine],
    nbFile,
    requestedFormats,
    activeFormats = {"md"},
    stripOutputs,
    converters,
    rawNb,
    cleanedNb,
    basePath,
    generatedFiles = {}
  },

    (* Function to discard output, message, print, and echo cells *)
    stripOutputs[nb_Notebook] := 
      nb //. {
        Cell[CellGroupData[cells_List, state___], opts___] :> 
          With[{filtered = DeleteCases[cells, Cell[_, "Output" | "Message" | "Print" | "Echo", ___]]},
            If[Length[filtered] == 1,
              First[filtered],
              Cell[CellGroupData[filtered, state], opts]
            ]
          ],
        CellGroupData[cells_List, state___] :> 
          With[{filtered = DeleteCases[cells, Cell[_, "Output" | "Message" | "Print" | "Echo", ___]]},
            If[Length[filtered] == 1,
              First[filtered],
              CellGroupData[filtered, state]
            ]
          ],
        Cell[_, "Output" | "Message" | "Print" | "Echo", ___] :> Sequence[]
      };

    (* Format Converters Registry: extensible for future formats *)
    converters = <|
      "md" -> Function[{nb, outFile},
        Export[outFile, nb, "Markdown", GeneratedAssetLocation -> None]
      ]
      (* Future format converters can be registered here:
         "wsnb" -> Function[{nb, outFile}, ...],
         "wl" -> Function[{nb, outFile}, ...]
      *)
    |>;

    If[Length[args] < 1,
      WriteString[$Output, "Usage: wolfram-git-export-formats.wls <notebook.nb> [formats...]\n"];
      Exit[1]
    ];

    nbFile = First[args];
    If[!FileExistsQ[nbFile],
      WriteString[$Output, "Error: File not found: " <> nbFile <> "\n"];
      Exit[1]
    ];

    requestedFormats = If[Length[args] >= 2,
      Rest[args],
      activeFormats
    ];

    rawNb = Quiet @ Import[nbFile, "NB"];
    If[!MatchQ[rawNb, _Notebook],
      WriteString[$Output, "Error: Failed to import valid Notebook expression from: " <> nbFile <> "\n"];
      Exit[1]
    ];

    cleanedNb = stripOutputs[rawNb];
    basePath = If[StringEndsQ[nbFile, ".nb", IgnoreCase -> True],
      StringDrop[nbFile, -3],
      nbFile
    ];

    Do[
      If[KeyExistsQ[converters, fmt],
        Module[{targetFile = basePath <> "." <> fmt, exportResult},
          exportResult = Quiet @ converters[fmt][cleanedNb, targetFile];
          If[exportResult =!= $Failed && FileExistsQ[targetFile],
            AppendTo[generatedFiles, targetFile];
            WriteString[$Output, targetFile <> "\n"],
            WriteString[$Messages, "Warning: Failed to export " <> fmt <> " for " <> nbFile <> "\n"]
          ]
        ],
        WriteString[$Messages, "Warning: Unknown format requested: " <> fmt <> "\n"]
      ],
      {fmt, requestedFormats}
    ];

    Exit[0]
  ]
];
