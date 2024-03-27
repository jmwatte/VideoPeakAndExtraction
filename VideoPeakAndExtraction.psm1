#helpermethod to analyze the results of ebur128 and return the peak level and the timecode of the peak level
function GetPeakLevel {
   
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Array
    )
    Write-Host "#analysing peak level"
    $maxM = [double]::MinValue
    $timeOfMaxM = $null
    $maxLRA = $null
    $Integrated = $null
    $measure = Measure-Command {
        foreach ($line in $Array) {
            if ($line -match 'pts_time:\s*([\d\.]+)') {
                $time = $Matches[1]
            }

            if ($line -match 'lavfi.r128.M=(-?[\d\.]+)') {
                $M = [double]$Matches[1]

                if ($M -gt $maxM) {
                    $maxM = $M
                    $timeOfMaxM = $time
                }
            }
            if ($line -match 'lavfi.r128.LRA=(-?[\d\.]+)') {
                $maxLRA = [double]$Matches[1]
            
            }
            if ($line -match 'lavfi.r128.I=(-?[\d\.]+)') {
                $Integrated = [double]$Matches[1]
            
            }


        } }

    Write-host "GetPeakLevel analysed in  $($measure.ToString('hh\:mm\:ss\:fff'))"

    # Return a hashtable with timecode and level
    return @{timecodeOfPeak = $timeOfMaxM; Maxlevel = $maxM; integradedLevel = $Integrated; LRA = $maxLRA } 
}

<#
.SYNOPSIS
A helper method to extract a subclip from a video file.

.DESCRIPTION
The Get-Subclip function takes an input file, start time, and end time, and extracts a subclip from the video file between the start and end times.

.PARAMETER InputFile
The path to the input video file.

.PARAMETER StartTime
The start time for the subclip in seconds.

.PARAMETER Duration
The length for the subclip in seconds.

.EXAMPLE
Get-Subclip -InputFile "C:\path\to\file.mp4" -StartTime 30 -Duration 60

This will extract a 60-second subclip from the file at "C:\path\to\file.mp4" starting at 30 seconds and ending at 90 seconds.

.NOTES
Make sure that the input file is a valid video file and that the start and end times are within the duration of the video.
#>
function Get-Subclip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputFile,
        [Parameter(Mandatory = $true)]
        [string]$StartTime,
        [Parameter(Mandatory = $true)]
        [string]$Duration,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )
    Write-Host "*extracting clip"
    # Run the ffmpeg command
    $measure = Measure-Command {
        ffmpeg -stats -hide_banner -loglevel error  -ss $StartTime -t $Duration -i $InputFile -map 0 -c copy $OutputFile # 2>&1 | Out-String
    }
    # Print the results
    Write-host "Get-Subclip finished in  $($measure.ToString('hh\:mm\:ss\:fff'))"
}


<#
.SYNOPSIS
    Finds the peak audio level in a video and saves it to a JSON file.

.DESCRIPTION
    The Find-VideoPeakLevel function analyzes a video file to find the peak audio level. It uses the ffmpeg tool to analyze the audio stream and outputs the peak level to a log file. It then saves this peak level to a JSON file in the same directory as the input video file.

.PARAMETER InputFile
    Specifies the path of the video file to analyze.

.EXAMPLE
    Find-VideoPeakLevel -InputFile "C:\Videos\example.mp4"

    This command analyzes the video file example.mp4, returns the peak audio level, and saves it to a JSON file named "example_peaklevel.json" in the "C:\Videos\" directory.

.NOTES
    The function requires the ffmpeg tool to be installed and accessible in the system's PATH. It also requires the GetPeakLevel function to be loaded.

.LINK
    https://github.com/username/repo
#>
function Find-VideoPeakLevel {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $InputFile,
        [Parameter(Mandatory = $false)]
        [int] $channel = 0,
        [Parameter(Mandatory = $false)]
        [switch]$forceOverwrite = $false,
        [switch] $collect = $false       
    )
    #get the directory from the inputfile and make a log.txt there
    write-host "*finding peak level for $InputFile(channel $channel)"
    $directoryPath = $directoryPath = [System.IO.Path]::GetDirectoryName($InputFile)
    $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $logname = "ch$($channel)_logPiekM.json"
    $log = Join-Path $directoryPath $logname
    #  $logT = $log -replace '\\', '\\' -replace ':', '\:'
    #  $logPiek = "'" + $logT + "'"
    $measure = Measure-Command {

        $re = ffmpeg -stats -hide_banner -loglevel error -i $InputFile -map 0:a:$($channel)  -filter:a ebur128=metadata=1,ametadata=mode=print:file='logPiekM.txt'  -f null - #no space after the comma before ametadata" 

        #        $re = ffmpeg -stats -hide_banner -loglevel error -i $InputFile -map 0:a:0 -filter:a:0 ebur128=metadata=1,ametadata=mode=print:file='logPiekM.txt'  -f null - #no space after the comma before ametadata" 
        $res = Get-Content logPiekM.txt | Select-String -Pattern "pts_time", "lavfi.r128.M", "lavfi.r128.LRA", "lavfi.r128.I"  
        #ffmpeg  -stats -loglevel error -i $($InputFile) -filter:a:0 astats=metadata=1:reset=20:length=2,ametadata=print:key=lavfi.astats.Overall.Max_level:file='logPeak.txt' -f null -

    }
    $filename = $OriginalFileName + "_" + $logname 
    $filepath = Join-Path $directoryPath $filename
    $checkedFilepath = (Get-InputAndOutputPaths -InputFile $filepath).OutPath

    write-host "Find-VideoPeakLevel finished in  $($measure.ToString('hh\:mm\:ss\:fff'))"

    $result = GetPeakLevel -Array $res #analyse the results of the ffmpeg command
    $output = New-Object PSObject -Property @{
        InputFile    = $InputFile
        audiochannel = @{
        ($channel.ToString()) = @{
                PeakLevel = $result
            }
        }
    } #turn it into json and save it to a file
    Write-Host "Ch$($Channel) Peak level: $($result.Maxlevel) dB at $($result.timecodeOfPeak) seconds(LRA=$($result.LRA),Integrated=$($result.integradedLevel))"
    if ($collect -eq $false) {
        $output | ConvertTo-Json -Depth 4 | Set-Content -Path $checkedFilepath
    
        Write-Host "saved at $checkedFilepath"
    }
    return $output, $checkedFilepath
}



<#
.SYNOPSIS
    Measures all audio tracks in a video file and saves the results to a JSON file.

.DESCRIPTION
    The Measure-VideoAllAudioTracks function uses ffprobe to get information about the audio streams in a video file.
    It then calls the Find-VideoPeakLevel function for each audio stream to measure the peak level.
    The results are saved to a JSON file in the same directory as the input file.

.PARAMETER InputFile
    The path to the video file to measure. This parameter is mandatory.

.EXAMPLE
    Measure-VideoAllAudioTracks -InputFile "F:\test\Thor.Love.And.Thunder.2022_hasPeakClip.mkv"

    This command measures all audio tracks in the specified video file and saves the results to a JSON file.

.NOTES
    The output JSON file is named after the input file with "_Measured_<number of audio streams>Ch.json" appended to the name.
    The JSON file contains an array of objects, each representing an audio stream in the video file.
    Each object has properties for the input file name and the results from the Find-VideoPeakLevel function.
#>
function Measure-VideoAllAudioTracks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputFile
    )

    write-host "*measuring all tracks"
    $measure = Measure-Command {
        $ffprobeOutput = & ffprobe -v quiet -print_format json -show_streams $InputFile | ConvertFrom-Json
        $audioStreams = $ffprobeOutput.streams | Where-Object { $_.codec_type -eq "audio" }
        $audioStreamsCount = $audioStreams.Count
        Write-Host "Number of audio streams: $audioStreamsCount"
        $directoryPath = [System.IO.Path]::GetDirectoryName($InputFile)
        $filename = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
        $filename = $filename + ".json"
        $Newfilename = Join-Path $directoryPath $filename

        $checkedFilepath = (Get-InputAndOutputPaths -InputFile $Newfilename -ExtraEndString "_Measured_$($audioStreamsCount)Ch").OutPath

        $audioChannels = 0 .. $($audioStreamsCount - 1) | ForEach-Object {
            Find-VideoPeakLevel $InputFile -channel $_ -collect
        }

        $output = New-Object PSObject -Property @{
            InputFile     = $InputFile
            audiochannels = $audioChannels | ForEach-Object { $_.audiochannel }
        }

        $output | ConvertTo-Json -Depth 4 | Set-Content -Path $checkedFilepath
    }
    Write-Host "saved at $checkedFilepath"
    Write-Host "Measure-VideoAllAudioTracks finished in  $($measure.ToString('hh\:mm\:ss\:fff'))"
}
#Measure-VideoAllAudioTracks -InputFile "F:\test\Thor.Love.And.Thunder.2022_hasPeakClip.mkv"
#helperfunction to check that the start and end times are within the clip
function Get-StartAndEndTimes {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile,
        [Parameter(Mandatory = $true)]
        [double]$Duration,
        [Parameter(Mandatory = $true)]
        [double]$Timecode
    )
    write-host "*getting start and end times"
    $measure = Measure-Command {
        $Length = (ffprobe -v error $InputFile -show_entries format=duration -of default=noprint_wrappers=1:nokey=1)
        # Make sure that the start time and duration does not exceed the beginning or end of the $Length
        $StartTime = $Timecode - $Duration / 2
        if ($StartTime -lt 0) { $StartTime = 0 }
        $EndTime = $Timecode + $Duration / 2
        
        # Make sure that the duration does not exceed the end of the $Length
        if ($EndTime -gt $Length) { $EndTime = $Length }
    }
    Write-Host "Get-StartAndEndTimes finished in $($measure.ToString('hh\:mm\:ss\:fff'))"

    return @{
        StartTime = $StartTime
        EndTime   = $EndTime
    }
}

<#
.SYNOPSIS
A helper method to get the input and output paths for a file operation.

.DESCRIPTION
The Get-InputAndOutputPaths function takes an input file path, an optional string to append to the output file name, an optional flag to force overwrite, and an optional flag to check if the input file exists. It generates an output file path based on the input file path and the extra string, and checks if the output file already exists. If the output file exists and the force overwrite flag is not set, it generates a new output file path with a number appended to the filename.

.PARAMETER InputFile
The path to the input file.

.PARAMETER ExtraEndString
An optional string to be appended to the filename of the output file.

.PARAMETER ForceOverwrite
An optional flag to force overwrite of the output file if it already exists. The default is false.

.PARAMETER CheckExistance
An optional flag to check if the input file exists. The default is false.

.EXAMPLE
Get-InputAndOutputPaths -InputFile "C:\path\to\file.mp4" -ExtraEndString "_edited" -ForceOverwrite $true -CheckExistance $true

This will check if the file at "C:\path\to\file.mp4" exists, generate an output file path "C:\path\to\file_edited.mp4", and overwrite the output file if it already exists.

.NOTES
Make sure that the input file path is valid and accessible.
#>
function Get-InputAndOutputPaths {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile,
        [Parameter(Mandatory = $false)]
        [string]$ExtraEndString = $null,
        [Parameter(Mandatory = $false)]
        [bool]$ForceOverwrite = $false,
        [Parameter(Mandatory = $false)]
        [switch]$CheckExistance = $false
    )

    # Check to see if the input file exists
    if ($CheckExistance -eq $true) {
        if (!(Test-Path $InputFile)) {
            Write-Error "Input file does not exist."
            return
        } 
    }

    # Take the filename and add $ExtraEndString to it
    $directoryPath = [System.IO.Path]::GetDirectoryName($InputFile)
    $filename = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $extension = [System.IO.Path]::GetExtension($InputFile)
    $OutPath = Join-Path $directoryPath ($filename + $ExtraEndString + $extension)

    if (Test-Path $OutPath) {
        if ($ForceOverwrite) {
            Remove-Item $OutPath -Force
        }
        else {
            $i = 2
            while (Test-Path $OutPath) {
                $newFileName = "{0}{1}({2}){3}" -f $filename, $ExtraEndString, $i, $extension
                $OutPath = Join-Path $directoryPath $newFileName
                $i++
            }
        }
    }

    return @{
        InputFile = $InputFile
        OutPath   = $OutPath
    }
}

<#
.SYNOPSIS
    Extracts a peak audio clip from a video.

.DESCRIPTION
    The Export-VideoPeakClip function analyzes a video file to find the peak audio level and extracts a clip of specified duration around the peak audio.

.PARAMETER InputFile
    Specifies the path of the video file to analyze.

.PARAMETER Duration
    Specifies the duration in seconds of the clip to extract.

.PARAMETER ForceOverwrite
    Specifies whether to overwrite the output file if it already exists. Default is false.

.EXAMPLE
    Export-VideoPeakClip -InputFile "C:\Videos\example.mp4" -Duration 10 -ForceOverwrite $true

    This command analyzes the video file example.mp4, extracts a 10-second clip around the peak audio, and overwrites the output file if it exists.

.NOTES
    The function requires the Get-Subclip and Find-VideoPeakLevel functions to be loaded.

.LINK
    https://github.com/username/repo
#>
function Export-VideoPeakClip {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $InputFile ,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [int] $Duration,
        [int] $channel = 0,
        [Parameter(Mandatory = $false)]
        [bool] $ForceOverwrite = $false      
    )
    #check to see if $duration is a number
    if ($Duration -isnot [int]) {
        Write-Error "Duration must be a number."
        return
    }
    write-host "*extracting peak clip"
    $Extra = "_hasPeak"
    $measure = Measure-Command {
        Get-InputAndOutputPaths -InputFile $InputFile -ExtraEndString $Extra -ForceOverwrite $ForceOverwrite
        $r = Find-VideoPeakLevel $inputfile -channel $channel
        $times = Get-StartAndEndTimes -InputFile $inputfile -Duration $Duration -Timecode $r.timecode

        Get-Subclip -InputFile $inputfile  -StartTime $times.StartTime -Duration $Duration -OutputFile $OutPath
    }
    write-host "Export-VideoPeakClip finished in $($measure.ToString('hh\:mm\:ss\:fff'))" 
    write-host "Video-Extractclip finished $inputfile to $OutPath"
    return $OutPath
}

<#
.SYNOPSIS
A helper method to find the peak levels for all videos in a directory.

.DESCRIPTION
The Find-VideosPeakLevels function takes a directory path and a file extension, finds all video files in the directory with the specified extension, and finds the peak level for each video file. It saves the peak levels in a JSON file in the same directory.

.PARAMETER path
The path to the directory to search.

.PARAMETER extension
The file extension to filter for (e.g., mkv, mp4).

.EXAMPLE
Find-VideosPeakLevels -path "C:\path\to\directory" -extension "mp4"

This will find all .mp4 files in the directory at "C:\path\to\directory", find the peak level for each file, and save the peak levels in a JSON file in the same directory.

.NOTES
Make sure that the directory path is valid and accessible, and that it contains video files with the specified extension.
#>
function Find-VideosPeakLevels {
    param (
        #the directory to search
        [Parameter (Mandatory = $true)]
        [string] $path,
        # extension to filter for mkv ... mp4 ...
        [Parameter(Mandatory = $true)]
        [string]$extension,
        [Parameter(Mandatory = $false)]
        [int] $channel = 0
    )
    Write-Host "*finding peak levels for all videos in $path"
    $extension = "*.{0}" -f $extension
    $pathtoJson = "{0}\{1}" -f $path, "peaklevels.json"
    $pathtoJson = (Get-InputAndOutputPaths $pathtoJson).OutPath
    $measure = Measure-Command {
        Get-ChildItem -Path $path -Filter $extension  | ForEach-Object {
            Find-VideoPeakLevel -InputFile $_.FullName -channel $channel
        }  | ConvertTo-Json | Set-Content -Path $pathtoJson }
    write-host "Find-VideosPeakLevels finished in $($measure.ToString('hh\:mm\:ss\:fff'))"
    return $pathtoJson

}

#read the previous output.json and extract a peakclip for each file and save them into a new directory called clips inside the directory where the videos are.
function Get-OneSubclipFromJson {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $item,
        [Parameter(Mandatory = $true)]
        $Duration,
        [Parameter(Mandatory = $false)]
        [int] $channel = 0

    )
    write-host "*extracting peak clip from $item.InputFile"
$channel=$channel.ToString()
    $inputFile = $item.InputFile
    $peakLevel = $item.audiochannel.$($channel).PeakLevel
    $times = Get-StartAndEndTimes -InputFile $inputFile -Duration $Duration -Timecode $peakLevel.timecodeOfPeak
    $paths = Get-InputAndOutputPaths -InputFile $inputFile -ExtraEndString "_hasPeakClip" 

    Get-Subclip -InputFile $inputFile -StartTime $times.StartTime -Duration $Duration -OutputFile $paths.OutPath
} 

# Read the JSON file
function Read-PeakJson {
    #get the path to the json file from the commandline or from $PathToJson
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $pathToJson,
        [Parameter(Mandatory = $false)]
        [string] $Duration = 600
    )           

    $jsonData = Get-Content -Path $pathToJson | ConvertFrom-Json

    # Loop through each item in the JSON data
    foreach ($item in $jsonData) {
        Get-OneSubclipFromJson -item $item -Duration $Duration
        
    }

}
Export-ModuleMember -Function Get-Subclip, Export-VideoPeakClip, Find-VideoPeakLevel, Find-VideosPeakLevels, Read-PeakJson, Get-OneSubclipFromJson, Get-StartAndEndTimes, Get-InputAndOutputPaths, Measure-VideoAllAudioTracks
#
#$null, $path = Find-VideoPeakLevel -InputFile "F:\test\Thor.Love.And.Thunder.2022_hasPeakClip.mkv"

#Read-PeakJson $path -Duration 60
#Find-VideosPeakLevels -Path "F:\test" -extension 'mkv'
#Get-ChildItem F:\test\ -Filter *wolf*json|Read-PeakJson -Duration 600 
#(get-content -LiteralPath   $((Get-ChildItem F:\test\ -Filter peaklevel*json).FullName) | ConvertFrom-Json) | ? { $_.PeakLevel.LRA -gt 20 } |%{ Get-OneSubclipFromJson $_ -Duration 600}
#measureall -videofile "F:\test\The.Wolf.of.Wall.Street.2013_hasPeakClip(2).mkv"
