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
    normalizeCodeCells,
    extractCode,
    extractMarkdown,
    exportMarkdown,
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

    (* Normalize code cells to BoxData if given as plain strings *)
    normalizeCodeCells[nb_Notebook] := 
      nb /. Cell[s_String, t:("Input" | "Code"), opts___] :> Cell[BoxData[s], t, opts];

    (* Export a cleaned notebook as Markdown without FrontEnd dependency *)
    exportMarkdown[nb_Notebook, outFile_String] := Module[{mdString, success = False},
      (* Primary method: ResourceFunction["ExportMarkdownString"] which runs purely in kernel via Chatbook *)
      mdString = Quiet @ Check[
        ResourceFunction["ExportMarkdownString"][normalizeCodeCells[nb]],
        $Failed
      ];
      
      (* Verify markdown was generated and did not fail *)
      If[StringQ[mdString] && StringLength[mdString] > 0 && !StringContainsQ[mdString, "First[$Failed]"],
        Quiet @ Export[outFile, mdString, "String"];
        If[FileExistsQ[outFile], success = True]
      ];

      (* Fallback: Try UsingFrontEnd with built-in Export *)
      If[!success,
        Module[{res},
          res = Quiet @ UsingFrontEnd[Export[outFile, nb, "Markdown", GeneratedAssetLocation -> None]];
          If[res =!= $Failed && FileExistsQ[outFile],
            Module[{content = Quiet @ Import[outFile, "Text"]},
              If[StringQ[content] && !StringContainsQ[content, "First[$Failed]"],
                success = True,
                Quiet @ DeleteFile[outFile];
                success = False
              ]
            ]
          ]
        ]
      ];

      If[success, outFile, $Failed]
    ];

    (* Flatten CellGroupData wrappers into a flat list of leaf cells *)
    flattenCellGroups[expr_] := Flatten[expr //. {
      CellGroupData[cells_List, ___] :> cells,
      Cell[CellGroupData[cells_List, ___], ___] :> cells
    }];

    (* Extract plain code string from code/input cell content *)
    extractCode[content_] := Module[{res},
      If[StringQ[content], Return[content]];
      
      (* Method 1: Using Chatbook CellToString if available *)
      res = Quiet @ Check[
        Module[{str = Wolfram`Chatbook`CellToString[Cell[If[Head[content] === BoxData, content, BoxData[content]], "Input"]]},
          If[StringQ[str],
            If[StringStartsQ[str, "```wl\n"], str = StringDrop[str, 6]];
            If[StringStartsQ[str, "```wolfram\n"], str = StringDrop[str, 11]];
            If[StringEndsQ[str, "\n```"], str = StringDrop[str, -4]];
            If[StringEndsQ[str, "```"], str = StringDrop[str, -3]];
            str,
            $Failed
          ]
        ],
        $Failed
      ];
      If[StringQ[res] && res =!= "$Failed", Return[res]];

      (* Method 2: FrontEndExportPacket via UsingFrontEnd *)
      res = Quiet @ Check[
        UsingFrontEnd[First[FrontEndExecute[FrontEnd`ExportPacket[If[Head[content] === BoxData, content, BoxData[content]], "InputText"]]]],
        $Failed
      ];
      If[StringQ[res] && res =!= "$Failed", Return[res]];

      (* Method 3: Fallback to vendored Mathematica2Jupyter *)
      If[FileExistsQ[vsnbPackagePath],
        Quiet @ Get[vsnbPackagePath];
        res = Quiet @ Mathematica2Jupyter`Private`processInput[content];
        If[StringQ[res], Return[res]]
      ];

      ToString[content, InputForm]
    ];

    (* Extract markdown text from non-code leaf cell *)
    extractMarkdown[cell_Cell] := Module[{md},
      (* Method 1: ResourceFunction["ExportMarkdownString"] *)
      md = Quiet @ Check[
        ResourceFunction["ExportMarkdownString"][Notebook[{cell}]],
        $Failed
      ];
      If[StringQ[md] && md =!= "$Failed" && !StringContainsQ[md, "First[$Failed]"],
        Return[StringTrim[md, "\n"]]
      ];

      (* Method 2: UsingFrontEnd or built-in ExportString *)
      md = Quiet @ UsingFrontEnd[ExportString[Notebook[{cell}], "Markdown", GeneratedAssetLocation -> None]];
      If[StringQ[md] && !StringContainsQ[md, "First[$Failed]"],
        Return[StringTrim[md, "\n"]]
      ];

      ToString[First[cell], InputForm]
    ];

    (* Convert a single leaf cell to a VSNB (VS Code notebook) cell association *)
    vsnbCellAssoc[cell_Cell] := Module[{style = cell[[2]], content = First[cell], kind, value, languageId},
      If[MemberQ[{"Input", "Code"}, style],
        kind = 2;
        languageId = "wolfram";
        value = extractCode[content],
        kind = 1;
        languageId = "markdown";
        value = extractMarkdown[cell]
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
      leafCells = Cases[flattenCellGroups[First[nb]], _Cell];
      cellAssocs = Map[vsnbCellAssoc, leafCells];
      Export[outFile, <|"cells" -> cellAssocs|>, "JSON"]
    ];

    (* Format Converters Registry: extensible for future formats *)
    converters = <|
      "md" -> Function[{nb, outFile},
        exportMarkdown[nb, outFile]
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
