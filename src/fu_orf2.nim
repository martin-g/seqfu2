#[
  =========================
  =========================
  NOT IN USE IN PRODUCTION
  =========================
  =========================
]#
import threadpool
import readfq
import iterutils
import docopt, strutils, tables, math
import os
import ./seqfu_utils

const NimblePkgVersion {.strdefine.} = "undef"
 
const version = if NimblePkgVersion == "undef": "<preprelease>"
                else: NimblePkgVersion


template echoVerbose(things: varargs[string, `$`]) =
  if verbose == true:
    stderr.writeLine(things)
 
template db(things: varargs[string, `$`]) =
  if debug == true:
  
    stderr.writeLine(things)

template initClosure(id,iter:untyped) =
  let id = iterator():auto{.closure.} =
    for x in iter:
      yield x

var
  verbose = false
  debug = false
  
type
    mergeCfg = tuple[join: bool, 
      minId: float, 
      minOverlap, 
      maxOverlap, 
      minorf: int, 
      scanreverse: bool,
      code: int,
      minreadlength: int]

proc length(self:FQRecord): int = 
  ## returns length of sequence
  self.sequence.len()

iterator codons(self: FQRecord) : string = 
  var i = 0
  var s = self.sequence.toUpperAscii
  while i < self.length - 2:
    let codon = s[i .. i+2]
    if codon.len == 3:
       yield codon
    i += 3

proc kmer2num*(kmer:string):int =
  ## converts a kmer string into an integer 0..4^(len-1)
  let baseVal = {'T': 0, 'C': 1, 'A': 2, 'G': 3, 'U': 0}.toTable
  let klen = len(kmer)
  var num = 0
  for i in 0..(klen - 1):
    try:
      let p = 4^(klen - 1 - i)
      num += p * baseVal[kmer[i]]
    except:
      num = -1
      break
  num

proc num2kmer*(num, klen:int):string =
  ## converts an integer into a kmer string given the number and length of kmer
  let baseVal = {0:'T', 1:'C', 2:'A', 3:'G'}.toTable
  var kmer = repeat(" ",klen)
  var n = num
  for i in 0..(klen - 1):
    let p = 4^(klen - 1 - i)
    var baseNum = int(n/p)
    kmer[i] = baseVal[baseNum]
    n = n - p*baseNum
  kmer

proc translateFastx*(self:FQRecord, code = 1): FQRecord = 
  ## translates a nucleotide sequence with the given genetic code number: 
  ##    https://www.ncbi.nlm.nih.gov/Taxonomy/Utils/wprintgc.cgi for codes
  var codeMap = 
    ["FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CCWWLLLLPPPPHHQQRRRRIIMMTTTTNNKKSS**VVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CCWWTTTTPPPPHHQQRRRRIIMMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CCWWLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CCWWLLLLPPPPHHQQRRRRIIMMTTTTNNKKSSSSVVVVAAAADDEEGGGG",
     "FFLLSSSSYYQQCC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "", "",
     "FFLLSSSSYY**CCWWLLLLPPPPHHQQRRRRIIIMTTTTNNNKSSSSVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CCCWLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CC*WLLLSPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CCWWLLLLPPPPHHQQRRRRIIMMTTTTNNKKSSGGVVVVAAAADDEEGGGG",
     "FFLLSSSSYYY*CCWWLLLLPPPPHHQQRRRRIIIMTTTTNNNKSSSSVVVVAAAADDEEGGGG",
     "",
     "FFLLSSSSYY*LCC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "", "", "", "",
     "FFLLSSSSYY**CCWWLLLLPPPPHHQQRRRRIIMMTTTTNNNKSSSSVVVVAAAADDEEGGGG",
     "FFLLSS*SYY*LCC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FF*LSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CCWWLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSSKVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CCGWLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYY**CC*WLLLAPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYYQQCCWWLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYYQQCCWWLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYYYYCC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYYEECC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG",
     "FFLLSSSSYYEECCWWLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"]
  var code = codeMap[code - 1]
  var transeq = newseq[char]()
  for codon in self.codons:
    let num = kmer2num(codon)
    if num != -1:
      transeq.add(code[num])
    else:
      transeq.add('-')
  result = self
  db(">>>", len(transeq), ", ", transeq[^1])
  db("Translated ", transeq.join)
  result.sequence = transeq.join

 
 

proc translateAll(input: FQRecord, opts: mergeCfg): seq[FQRecord] =
  var
    rawprots : seq[FQRecord]
    seqs = @[input]
  db("Translating: " , input.name, " min=", opts.minorf)
  if opts.scanreverse == true:
    seqs.add(input.revcompl()) 

  # First translate all the frames
  for sequence in seqs:
    if len(sequence.sequence) < opts.minreadlength:
      
      break
    for frame in @[0, 1, 2]:
      let
        dna = sequence.sequence[frame .. ^1]
      var
        obj : FQRecord
      obj.name = if opts.scanreverse == false or sequence == input: "+" &  $frame
                else: "-" & $frame
      obj.sequence = dna
      obj.sequence = obj.translateFastx(opts.code).sequence
      rawprots.add( obj )
  
  # Then split on STOP codons
  for translatedRecord in rawprots:
    var
      orf = ""
      start = 0
     

    for i, aa in translatedRecord.sequence:
      #db("i=", i, " aa=", aa, " orf=", orf, " len=", len(translatedRecord.seq))
      if aa == '*' or i == len(translatedRecord.sequence) - 1:
        
        orf = if aa == '*': translatedRecord.sequence[start ..< i]
              else: translatedRecord.sequence[start .. i]
        db(" orf=",orf)
        if len(orf) >= opts.minorf:
           
          var
            obj : FQRecord
          db( " ORF: ", $i)
          obj.name = translatedRecord.name & " start=" & $start
          obj.sequence = orf
          result.add( obj )
           
        start = i + 1
        orf = ""
      

#[      
  for translatedseq in rawprots:
     
    let translations : seq = translatedseq.sequence.split('-')
     
    for t in translations:
      if len(t) > minOrfSize:
        let orfs = t.split('*')
         
        for orf in orfs:
          if len(orf) > minOrfSize:
            var s: FQRecord
            s.name = translatedseq.name
            s.sequence = orf
            result.add(s)
]#      
  
proc mergePair(R1, R2: FQRecord, minlen=10, minid=0.85, identityAccepted=0.90): FQRecord {.discardable.} = 
  var REV = revcompl(R2) 
  var max = if R1.sequence.high > REV.sequence.high: REV.sequence.high
          else:  R1.sequence.high
  
  var max_score = 0.0
  var pos = 0
  var str : string

  for i in minlen .. max:
    var
      s1 = R1.sequence[R1.sequence.high - i .. R1.sequence.high]
      s2 = REV.sequence[0 .. 0 + i ]
      #q1 = R1.qual[R1.sequence.high - i .. R1.sequence.high]
      #q2 = R2.qual[R2.sequence.high - i .. R2.sequence.high]
      score = 0.0
      

    for i in 0 .. s1.high:
      if s1[i] == s2[i]:
        score += 1
   
    score = score / float(len(s1))

    if score > max_score:
      max_score = score
      pos = i
      str = s1
      if score > identityAccepted:
        break
  # end loop

  # Fix mismatches
  if max_score > min_id:
    result.name = R1.name
    result.sequence = R1.sequence & REV.sequence[pos + 1 .. ^1]
    result.quality = R1.quality & REV.quality[pos + 1 .. ^1]
  else:
    result = R1

proc processPair(R1, R2: FQRecord, opts: mergeCfg): string =
  var
    orfs: seq[FQRecord]
    s1: FQRecord
    joined = false
    counter = 0

  if opts.join:
    s1 = mergePair(R1, R2, opts.minOverlap, opts.minId)
    
    if length(s1) == length(R1):
      joined = false
    else:
      joined = true

  if joined == true:
    orfs.add( translateAll(s1, opts) )
  else:
    orfs.add( translateAll(R1, opts))
    orfs.add( translateAll(R2, opts))
  
  for peptide in orfs:
    counter += 1
    
    result &= '>' & R1.name & "_" & $counter & " frame=" & peptide.name & " tot=" & $(len(orfs)) & "\n" & peptide.sequence & "\n"


proc processSingle(R1: FQRecord, opts: mergeCfg): string =
  var
    orfs: seq[FQRecord]
    counter = 0
    
  orfs.add( translateAll(R1, opts))
  
  for peptide in orfs:
    counter += 1
    result &= '>' & R1.name & "_" & $counter & " frame=" & peptide.name & " tot=" & $(len(orfs)) & "\n" & peptide.sequence & "\n"

    
proc parseArray(pool: seq[FQRecord], opts: mergeCfg): string =
  for i in 0 .. pool.high:
    if i mod 2 == 1:
      try:
        result &= processPair(pool[i - 1], pool[i], opts)  
      except:
        result &= processPair(pool[i - 1], pool[i], opts) 
        quit()

proc parseArraySingle(pool: seq[FQRecord], opts: mergeCfg): string =
  for i in 0 .. pool.high:
    try:
      result &= processSingle(pool[i], opts)  
    except:
      result &= processSingle(pool[i], opts) 
      quit()
  

proc printCodes() =
  echo """NCBI Genetics Codes: 

  1.  The Standard Code
  2.  The Vertebrate Mitochondrial Code
  3.  The Yeast Mitochondrial Code
  4.  The Mold, Protozoan, and Coelenterate Mitochondrial Code and the Mycoplasma/Spiroplasma Code
  5.  The Invertebrate Mitochondrial Code
  6.  The Ciliate, Dasycladacean and Hexamita Nuclear Code
  9.  The Echinoderm and Flatworm Mitochondrial Code
  10. The Euplotid Nuclear Code
  11. The Bacterial, Archaeal and Plant Plastid Code
  12. The Alternative Yeast Nuclear Code
  13. The Ascidian Mitochondrial Code
  14. The Alternative Flatworm Mitochondrial Code
  16. Chlorophycean Mitochondrial Code
  21. Trematode Mitochondrial Code
  22. Scenedesmus obliquus Mitochondrial Code
  23. Thraustochytrium Mitochondrial Code
  24. Rhabdopleuridae Mitochondrial Code
  25. Candidate Division SR1 and Gracilibacteria Code
  26. Pachysolen tannophilus Nuclear Code
  27. Karyorelict Nuclear Code
  28. Condylostoma Nuclear Code
  29. Mesodinium Nuclear Code
  30. Peritrich Nuclear Code
  31. Blastocrithidia Nuclear Code
  33. Cephalodiscidae Mitochondrial UAA-Tyr Code
    
See also: https://www.ncbi.nlm.nih.gov/Taxonomy/Utils/wprintgc.cgi"""

proc fastx_orf(argv: var seq[string]): int =
  let args =  docopt("""
  fu-orf
 
  Extract ORFs from Paired-End reads.

  Usage: 
  fu-orf [options] <InputFile>  
  fu-orf [options] -1 File_R1.fq
  fu-orf [options] -1 File_R1.fq -2 File_R2.fq
  fu-orf --help | --codes
  
  Input files:
    -1, --R1 FILE           First paired end file
    -2, --R2 FILE           Second paired end file

  ORF Finding and Output options:
    -m, --min-size INT      Minimum ORF size (aa) [default: 25]
    -p, --prefix STRING     Rename reads using this prefix
    -r, --scan-reverse      Also scan reverse complemented sequences
    -c, --code INT          NCBI Genetic code to use [default: 1]
    -l, --min-read-len INT  Minimum read length to process [default: 25]
  
  Paired-end optoins:
    -j, --join              Attempt Paired-End joining
    --min-overlap INT       Minimum PE overlap [default: 12]
    --max-overlap INT       Maximum PE overlap [default: 200]
    --min-identity FLOAT    Minimum sequence identity in overlap [default: 0.80]
  
  Other options:
    --codes                 Print NCBI genetic codes and exit
    --pool-size INT         Size of the sequences array to be processed
                            by each working thread [default: 250]
    --verbose               Print verbose log
    --debug                 Print debug log  
    --help                  Show help
  """, version=version, argv=argv)

  var
    fileR1, fileR2: string
    minOrfSize, counter: int
    mergeOptions: mergeCfg
    minreadlen: int
    poolSize : int
    prefix : string
    singleEnd = true
    code: int
     
  debug = args["--debug"]
  try:
    fileR1 = $args["--R1"]
    fileR2 = $args["--R2"]
    code = parseInt($args["--code"])
    minreadlen = parseInt($args["--min-read-len"])
    minOrfSize = parseInt($args["--min-size"])
    verbose = args["--verbose"]
    poolSize = parseInt($args["--pool-size"])
    prefix = $args["--prefix"]
    mergeOptions = (join: args["--join"] or false,  
      minId: parseFloat($args["--min-identity"]), 
      minOverlap: parseInt($args["--min-overlap"]), 
      maxOverlap: parseInt($args["--max-overlap"]), 
      minorf: minOrfSize, 
      scanreverse: args["--scan-reverse"] or false,
      code: code,
      minreadlength: minreadlen)
  except:
    stderr.writeLine("Use fu-orf --help")
    stderr.writeLine("Arguments error: ", getCurrentExceptionMsg())
    quit(0)
 
  if args["--codes"]:
    echo "SeqFu ORF"
    echo "--------------------------------------------------------"
    printCodes()
    quit(0)

  let
    validCodes = @[1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14, 16, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 33]
  
  if not validCodes.contains(code):
    printCodes()
    stderr.writeLine("Invalid genetic code: ", code)
    stderr.writeLine("Valid codes: ", validCodes)
    quit(1)

  echoVerbose("SeqFu ORF")
#[
    if len(fileR1) == 0:
    verbose("Missing required parameters: -1 FILE1 [-2 FILE2]", true)
    quit(0)
 ]#

  if args["<InputFile>"]:
    fileR1 = $args["<InputFile>"]
    singleEnd = true
    if fileExists(fileR1):
      echoVerbose("Single file: " & fileR1)
    else:
      echo("ERROR: Single file not found:", fileR1)
      quit(0)

  elif len(fileR1) > 0 and fileR2 == "nil":
    singleEnd = true
    if fileExists(fileR1):
      echoVerbose("Single end mode [-1]: ", fileR1)
    else:
      echo("ERROR: File not found [-1]:", fileR1)
      quit(0)
  elif len(fileR1) > 0 and fileR2 != "nil":
    singleEnd = false
    if fileExists(fileR1) and fileExists(fileR2):
      echoVerbose("Paired end mode [-1] and [-2]: ", fileR1, " and ", fileR2)
    else:
      if not fileExists(fileR1):
        echo("ERROR: File not found [-1]: ", fileR1)
      if not fileExists(fileR2):
        echo("ERROR: File not found [-2]: ", fileR2)
      quit(0) 
  else:
    echoVerbose("ERROR: Missing required parameters", fileR1, fileR2)
    quit(0)

  if not fileExists(fileR1):
    stderr.writeLine("FATAL ERROR: File [-1] ", fileR1, " not found.")
    quit(1)
  if fileR2 != "nil" and not fileExists(fileR2):
    stderr.writeLine("FATAL ERROR: File [-2] ", fileR2, " not found.")
    quit(1)
  elif fileR2 == "nil":
    echoVerbose("Single end mode")
    singleEnd = true
  
  var
    read1, read2: FQRecord
  echoVerbose("Reading R1:" & fileR1)


  
  var readspool : seq[FQRecord]
  var responses = newSeq[FlowVar[string]]()

  if not singleEnd:
    ##
    ## Paired End Mode
    ##
    initClosure(f1,readfq(fileR1))
    #creates a new closure iterator, 'f1'

    initClosure(f2,readfq(fileR2))
    #creates a new closure iterator, 'f2'
    
    for raw_read_1, raw_read_2 in zip(f1,f2):
      read1 = raw_read_1
      read2 = raw_read_2
     
      
      counter += 1
      if prefix != "nil":
        read1.name = prefix & $counter
        read2.name = prefix & $counter
  
      
      readspool.add(read1)
      readspool.add(read2)  

      if counter mod poolSize == 0:
        responses.add(spawn parseArray(readspool, mergeOptions))
        readspool.setLen(0)

    # Empty queue
    responses.add(spawn parseArray(readspool, mergeOptions))
    

  else:
    ##
    ## Single End Mode
    ##
    for fq_record in readfq(fileR1):
      counter += 1
      read1= fq_record

      
      if prefix != "nil":
        read1.name = prefix & $counter
         
      readspool.add(read1)
      if counter mod poolSize == 0:
        responses.add(spawn parseArraySingle(readspool, mergeOptions))
        readspool.setLen(0)

 
    responses.add(spawn parseArraySingle(readspool, mergeOptions))
    
  for resp in responses:
    let s = ^resp
    stdout.write(s)


when isMainModule:
  main_helper(fastx_orf)
