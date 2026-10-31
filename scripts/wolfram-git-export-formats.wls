#!/usr/bin/env wolframscript
(* ::Package:: *)
(* wolfram-git-export-formats.wls: Export Wolfram notebooks to companion formats (markdown, etc.) with output cells discarded *)

Quiet[
  Module[{
    args = Rest[$ScriptCommandLine],
    nbFile,
    requestedFormats,
    activeFormats = {"md", "vsnb"},
    stripOutputs,
    flattenCellGroups,
    vsnbCellAssoc,
    exportVSNB,
    scriptDir,
    vsnbPackagePath,
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

    (* Locate the vendored mathematica2jupyter package (used for code-cell text extraction) *)
    scriptDir = If[StringQ[$InputFileName] && $InputFileName =!= "",
      DirectoryName[$InputFileName],
      DirectoryName[First[$ScriptCommandLine]]
    ];
    vsnbPackagePath = FileNameJoin[{scriptDir, "Mathematica2Jupyter.wl"}];

    (* Flatten CellGroupData wrappers into a flat list of leaf cells *)
    flattenCellGroups[expr_] := Flatten[expr //. {
      CellGroupData[cells_List, ___] :> cells,
      Cell[CellGroupData[cells_List, ___], ___] :> cells
    }];

    (* Convert a single leaf cell to a VSNB (VS Code notebook) cell association *)
    vsnbCellAssoc[cell_Cell] := Module[{style = cell[[2]], content = First[cell], kind, value, languageId},
      If[MemberQ[{"Input", "Code"}, style],
        kind = 2;
        languageId = "wolfram";
        value = Module[{input = Quiet @ Mathematica2Jupyter`Private`processInput[content]},
          If[StringQ[input], input, ToString[content, InputForm]]
        ],
        kind = 1;
        languageId = "markdown";
        value = Module[{md = Quiet @ ExportString[Notebook[{cell}], "Markdown", GeneratedAssetLocation -> None]},
          If[StringQ[md], StringTrim[md, "\n"], ToString[content, InputForm]]
        ]
      ];
      <|"kind" -> kind,
        "value" -> value,
        "languageId" -> languageId,
        "outputs" -> {},
        "metadata" -> <||>,
        "executionSummary" -> <||>|>
    ];

    (* Export a cleaned notebook as a VSNB (VS Code notebook) file *)
    exportVSNB[nb_Notebook, outFile_String] := Module[{leafCells, cellAssocs},
      If[!FileExistsQ[vsnbPackagePath],
        WriteString[$Messages, "Warning: VSNB export requires " <> vsnbPackagePath <> "\n"];
        Return[$Failed]
      ];
      Get[vsnbPackagePath];
      leafCells = Cases[flattenCellGroups[First[nb]], _Cell];
      cellAssocs = Map[vsnbCellAssoc, leafCells];
      Export[outFile, <|"cells" -> cellAssocs|>, "JSON"]
    ];

    (* Format Converters Registry: extensible for future formats *)
    converters = <|
      "md" -> Function[{nb, outFile},
        Export[outFile, nb, "Markdown", GeneratedAssetLocation -> None]
      ],
      "vsnb" -> Function[{nb, outFile},
        exportVSNB[nb, outFile]
      ]
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
