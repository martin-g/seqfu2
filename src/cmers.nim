import readfq
import docopt
import os
import kmer
import threadpool
import strutils, strformat
import tables, algorithm
import ./seqfu_utils

const NimblePkgVersion {.strdefine.} = "undef"
const version = if NimblePkgVersion == "undef": "1.0"
                else: NimblePkgVersion



type
  makeDbOptions = object
    kmerSize: int
    windowSize: int
    verbose: bool
type
  scanOptions = object
    kmerSize: int
    windowSize: int
    verbose: bool
    stepSize: int
    minCount: int
    poolSize: int

proc compressHomopolymers(s: string): string =
  result  = $s[0]
  for c in s[1 .. ^1]:
    if c != result[^1]:
      result = result & c

proc makeDb(inputfile: string, options: makeDbOptions): int =
  var
    countTable = initCountTable[uint64]()
  for read in  readfq(inputfile):
    let sequence = compressHomopolymers(read.sequence)
    for i in 0 ..< (len(sequence) - options.kmerSize):
      let kmer = sequence[i ..< i + options.kmerSize]
      countTable.inc(encode(kmer))
  for k, count in countTable.pairs():
    var kmer = newString(options.kmerSize)
    decode(k, kmer)
    echo kmer
  return 0



proc loadKmerList(filename: string, kmerSize: int): seq[string] =
  for line in lines filename:
    if len(line) != kmerSize:
      stderr.writeLine("Malformed line [exp ", kmerSize, "-mer]: ", line)
      quit(1)
    result.add(line)

proc scanRead(read: FQRecord, db: seq[string], options: scanOptions): bool =
  let sequence = compressHomopolymers(read.sequence)
  for j in countup(0, len(sequence) - options.windowSize, options.stepSize):
          var hits = 0
          let window = sequence[j ..< j + options.windowSize]
          for i in 0 ..< (len(window) - options.kmerSize):
            let kmer = window[i ..< i + options.kmerSize]
            if db.contains(kmer):
              hits += 1
          if hits >= options.minCount:
            return true
  return false

proc processReadPool(pool: seq[FQRecord], db: seq[string], o: scanOptions): seq[FQRecord] =
  # Receive a set of sequences to be processed and returns them as string to be printed
  for read in pool:
     if scanRead(read, db, o):
       result.add(read)

proc main(argv: var seq[string]): int =
  let args = docopt("""
  Compressed-mers

  A program to select long reads based on a compressed-mers dictionary

  Usage: 
  cmers scan [options] <DB> <FASTQ>...
  cmers make [options] <DB> 

  Make db options:
    -k, --kmer-size INT    K-mer size [default: 31]
    -o, --output-file STR  Output file [default: stdout]

  Scanning options:
    -w, --window-size INT  Window size [default: 1500]
    -s, --step INT         Step size [default: 350]
    --min-len INT          Discard reads shorter than INT [default: 500]
    --min-hits INT         Minimum number of hits per windows [default: 50]
  
  Multithreading options:
    --pool-size INT        Number of sequences per thread pool [default: 1000]
     
    --verbose              Print verbose log
    --help                 Show help
  """, version=version, argv=argv)
 
  let
    makeOpts = makeDbOptions(
      kmerSize : parseInt($args["--kmer-size"]),
      windowSize : parseInt($args["--window-size"]),
      verbose : args["--verbose"]
    )
 

    
  if args["make"]:
    quit(makeDb($args["<DB>"], makeOpts))

  setMaxPoolSize(64)
    
  # Prepare options
  let opts = scanOptions(
    kmerSize: parseInt($(args["--kmer-size"])),
    windowSize: parseInt($(args["--window-size"])),
    verbose: args["--verbose"],
    stepSize: parseInt($(args["--step"])),
    minCount: parseInt($(args["--min-hits"])),
    poolSize: parseInt($(args["--pool-size"])),
  )

  let minReadLen = parseInt($(args["--min-len"]))

  # Prepare the database
  let db = loadKmerList($args["<DB>"], parseInt($(args["--kmer-size"])) )
  if opts.verbose:
    stderr.writeLine "Loaded ", len(db), " kmers"

  # Process file read by read
  for file in @(args["<FASTQ>"]):
    var outputSeqs = newSeq[FlowVar[seq[FQRecord]]]()
    var readspool : seq[FQRecord]
    var seqCounter = 0

    if not fileExists(file):
      stderr.writeLine("ERROR: File <", file, "> not found. Skipping.")
      continue

    try:
      # Process input file
      for seqObject in readfq(file):

        if len(seqObject.sequence) < minReadLen:
          continue

        seqCounter += 1
        readspool.add(seqObject)
 
        if len(readspool) >= opts.poolSize:
          outputSeqs.add(spawn processReadPool(readspool, db, opts))
          readspool.setLen(0)
    

      

    except Exception as e:
      stderr.writeLine("ERROR: Unable to parse FASTX file: ", file, "\n", e.msg)
      return 1
    
    # Last reads
    if len(readspool) > 0:
      outputSeqs.add(spawn processReadPool(readspool, db, opts))

    # Collect results
    var
      poolId = 0 
      printedSeqs = 0

    for resp in outputSeqs:
      let
        filteredReads = ^resp
        totFiltCurrentPool = len(filteredReads)

      printedSeqs += totFiltCurrentPool
      poolId += 1
      if opts.verbose and totFiltCurrentPool > 0:
        stderr.writeLine poolId, ": printing ", totFiltCurrentPool, " sequences."
      for read in filteredReads:
        echo read

    if opts.verbose:
      stderr.writeLine "Total printed sequences: ", printedSeqs
  

when isMainModule:
  main_helper(main)