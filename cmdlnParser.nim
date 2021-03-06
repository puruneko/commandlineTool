import os
import system
import strutils
import sequtils
import strformat
import typetraits
import macros

type
  CmdlnOptions = enum
    REQUIRED,
    BAN_MULTIPLE,
    LIMIT_MULTIPLE,
    USE_MULTIPLE_SEPARATOR

  CmdlnParser = object
    params: tuple
    pre: string
    sep: string
    help: string
    results: tuple

  CmdlnParam*[T] = object
    keyword: string
    description: string
    parseProc: proc (p: string): T
    default: T
    defaultFlag: bool
    res: seq[T]

macro getAnyType(x: typed): auto =
  parseStmt($x.getTypeInst.toStrLit)

macro getProcReturnType(p: proc): auto =
  var res = "void"
  let typeTree = p.getTypeInst
  for t in typeTree:
    if t.kind == NimNodeKind.nnkFormalParams:
      if t[0].kind == NimNodeKind.nnkNone:
        res = "void"
      else:
        res = $t[0].toStrLit
  parseStmt(res)

proc newCmdParam*(keyword: string, desc="", parseProc: proc): auto =
  proc newCmdParamTypedesc[T](keyword: string, desc: string, parseProc: proc (p: string): T): CmdParam[T] =
    result.keyword = keyword
    result.description = desc
    result.parseProc = parseProc
    result.defaultFlag = false
  result = newCmdParamTypedesc[getProcReturnType(parseProc)](keyword, desc, parseProc)

proc newCmdParam*(keyword: string, desc="", parseProc: proc, default: not proc): auto =
  result = newCmdParam(keyword, desc, parseProc)
  result.default = default
  result.defaultFlag = true

proc newCmdParam*(keyword: string, desc="", default: not proc): auto =
  proc newCmdParamTypedesc[T](keyword:string, desc: string, default: T): CmdParam[T] =
    result.keyword = keyword
    result.description = desc
    result.default = default
    result.defaultFlag = true
    result.parseProc = proc (p: string): T = cast[T](p)
    when T is string:
      result.parseProc = proc (p: string): string = p
    elif T is int:
      result.parseProc = proc (p: string): int = parseInt(p)
    elif T is float:
      result.parseProc = proc (p: string): float = parseFloat(p)
  result = newCmdParamTypedesc[getAnyType(default)](keyword, desc, default)

macro len(t: tuple): int =
  len(t)

macro extractObjectElementInTuple(definedTpl: typed, objectElementName: static[string]): auto =
  let length = len(definedTpl.getTypeInst)
  var elemStrSeq: seq[string]
  for itr in 0..<length:
    elemStrSeq.add($definedTpl.toStrLit & "[" & $itr & "]." & objectElementName)
  var command = "(" & elemStrSeq.join(",") & ")"
  parseStmt(command)

proc newCmdlnParser(results: tuple = (), pre="--", sep=":", help="h", params: var tuple): CmdlnParser =
  result.pre = pre
  result.sep = sep
  result.help = help
  var typeSeq: seq[string] = @[]
  for param in params:
    discard


proc parseCmdLineParams*(cmdParamSeq: seq[string], pre="--", sep=":", help="h", params: var tuple): auto =
  const tab = "\t"
  let length = len(params)
  var fixedCmd: string
  for cmdParam in cmdParamSeq:
    for prm in params.fields:
      fixedCmd = pre & prm.keyword & sep
      if cmdParam.startsWith(fixedCmd):
        try:
          prm.res.add(prm.parseProc(cmdParam.replace(fixedCmd, "")))
        except:
          echo fmt"[ParseCommandLineParam ERR]convert type error at keyword {fixedCmd}:"
          echo fmt"  -> can not convert {cmdParam}."
          echo fmt"    -> ignore."
    if cmdParam == pre & help:
      echo "---------- command line help ----------"
      echo fmt"input rule: {pre}keyword{sep}value"
      echo    "legend: keyword [type]: description\n"
      for prm in params.fields:
        var prm2 = prm
        echo fmt"{prm2.keyword}  {tab}[{getProcReturnType(prm2.parseProc)}]: {prm2.description}"
      echo "---------------------------------------"
  for prm in params.fields:
    if len(prm.res) == 0:
      if prm.defaultFlag:
        prm.res = @[prm.default]
  result = extractObjectElementInTuple(params, "res")

# get scolded by Macro if DummyType definition is not located at global scope...
type
  DummyType[T] = object
    value: T

proc toDummyType(p: string): DummyType[string] =
  result.value = p

proc pcharProcessing(p: string): string =
  "pchar=" & p

if isMainModule:
  var cmdlnParser = newCmdlnParser(
    params=(
      newCmdlnParam("pstr",defalut="test",output="strs"),
      newCmdlnParam("pint",default=1,output="ints",options=[LIMIT_MULTIPLE,2]),
      newCmdlnParam("pfloat",default=1.0,options=BAN_MULTIPLE),
      newCmdlnParam("pchars",parseProc=pcharProcessing,output="strs"), # after processed by 'pcharProcessing', merge to strs result group
      newCmdlnParam("pdoc",output="strs"),
      newCmdlnParam("pdummy",parseProc=toDummyType,output="dummys") # if without default setting, option is set REQUIRED automatically.
    ),
    output=("ints","strs","dummys"),
    pre="==",
    sep="::",
  )
  var sampleInput: seq[string] = "==pfloat::2.0 ==pstr::a ==pchars::b ==pdummy::x".split(" ")
  var res = cmdlnParser.parse(sampleInput)
  for x in val.fields:
    echo x