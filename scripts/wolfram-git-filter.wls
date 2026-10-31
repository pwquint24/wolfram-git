#!/usr/bin/env wolframscript
(* ::Package:: *)
(* wolfram-git-filter.wls: Git clean filter for Wolfram notebooks using SaveReadableNotebook *)

Quiet[
  Module[{rawContent = "", nb, tmpFile, cleanedContent, success = False, args = $ScriptCommandLine},
    (* Check if a filename argument was passed and exists *)
    If[Length[args] >= 2 && StringQ[args[[2]]] && FileExistsQ[args[[2]]],
      rawContent = Quiet @ Import[args[[2]], "Text"],
      (* Otherwise read from standard input *)
      If[StringQ[$ScriptInputString] && StringLength[$ScriptInputString] > 0,
        rawContent = $ScriptInputString
      ]
    ];

    If[StringLength[StringTrim[rawContent]] > 0,
      nb = Quiet @ ImportString[rawContent, "NB"];
      If[MatchQ[nb, _Notebook],
        tmpFile = CreateFile[];
        If[StringQ[tmpFile] && FileExistsQ[tmpFile],
          Quiet @ ResourceFunction["SaveReadableNotebook"][nb, tmpFile];
          cleanedContent = Quiet @ Import[tmpFile, "Text"];
          Quiet @ DeleteFile[tmpFile];
          If[StringQ[cleanedContent] && StringLength[cleanedContent] > 0,
            WriteString[$Output, cleanedContent];
            success = True
          ]
        ]
      ];
      (* Fallback: if cleaning failed or input was not a valid Notebook, output raw content *)
      If[!success,
        WriteString[$Output, rawContent]
      ]
    ]
  ]
];

Exit[0];
