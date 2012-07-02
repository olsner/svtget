#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# SVTGet v0.7.0 in ruby
# Updates can be found at https://github.com/mmn/svtplay
# Support the project with Flattr: https://flattr.com/thing/300374/SVT-Get-a-local-cache-tool-for-SVT-Play

# Description: The script can download the RTMP streams available from the
# online streaming service "SVT Play", managed by Sveriges Television
#
# Original author: Simon Gate
# Current Maintainer: Erik Modén
# License: GPLv3
# http://www.gnu.org/licenses/gpl-3.0.txt
#
# The original bash script was created by Mikael "MMN-o" Nordfeldth
# URL: http://blog.mmn-o.se/
# Flattr: https://flattr.com/thing/188162/MMN-o-on-Flattr

require 'optparse'
require 'net/http'
require 'uri'
require 'hpricot'
require 'json'


def checkIfIntalled( progs )
  missing = progs.select{|prog| !system("which #{prog} > /dev/null 2>&1") }
  if ! missing.empty?
    missing.each{|prog| puts "#{File.basename(__FILE__)} is depending on #{prog}, please install it and #{File.basename(__FILE__)} will start working." }
    exit 1
  end
end

dependencies = [ 'rtmpdump', 'curl', 'ffmpeg', 'ffplay' ]

checkIfIntalled dependencies

svtplayUrl = "http://www.svtplay.se"

# Available bitrates at svtplay
bitrates = { 'l' => 340, 'm' => 850, 'n' => 1400, 'h' => 2400}

@options = { :bitrate => 0, :silent => false, :subtitles => false, :debug => false, :app => 'rtmpdump', :xargs => '',  :extension => '' }

# Options
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options] #{svtplayUrl}/..."
  opts.on("-q", "--quality [l|m|n|h]", "Quality of the stream #{bitrates}") do |q|
    @options[:bitrate] = bitrates[q]
  end
  opts.on("-p", "--play", "Plays the stream with ffplay") do
    @options[:app] = 'ffplay'
  end
  opts.on("-s", "--subtitles", "Fetch subtitles") do
    @options[:subtitles] = true
  end
  opts.on("-t", "--transcode", "Transcod with ffmpeg, use -x pass args to ffmpeg") do
    @options[:app] = 'ffmpeg'
  end
  opts.on("-e", "--extension extension", "Extension for transcod output") do |e|
    @options[:extension] = e
  end
  opts.on("-x", '--xargs "ARGS..."', "Args to pass on to the launched application") do |args|
    @options[:xargs] = args
  end
  opts.on("--silent", "Don't output any information") do
    @options[:silent] = true
  end
  opts.on("--debug", "Dry run, only prints the cmd") do
    @options[:debug] = true
  end
  opts.on("-?", "--help", "Show this help") do
    puts opts
    exit
  end

end

optparse.parse!
# Check if SVT play URL was given, else DIE!
if !ARGV[0].nil? && ARGV[0].match(/#{svtplayUrl}/)  
  htmlText = Net::HTTP.get URI.parse("#{ARGV.shift}?type=embed")
  ARGV.clear
  html = Hpricot( htmlText )
  
  def getEpisodAndProgramName( html )
    title = (html/"[@data-title]").first['data-title']
    episod = title[/^(.*)\s+-\s+/,1]
    program = title[/\s+-\s+(.*)\s+\|/,1]
    if ! ( episod && program )
      program =  title[/^(.*):\s+/,1]
      episod =  title[/:\s+(.*)\s+\|/,1]
      if program =~ /^\d+\/\d+/
	program = nil
      end
    end
     if ! (episod || program)
      episod =  title[/^(.*)\s+\|/,1]
    end   
    return episod, program
  end
  
  episod, program = getEpisodAndProgramName html
 
  playerParam = (html/"[@name='movie']").first
  playerValueStr = playerParam.attributes["value"]
  player = svtplayUrl + playerValueStr
  flashParam = (html/"[@name='flashvars']").first
  jsonValueStr = flashParam.attributes["value"]
  flashData = JSON.parse( jsonValueStr.sub( /^json=/, "" ) )
  subtitlesList = flashData["video"]["subtitleReferences"]
  allStreams = flashData["video"]["videoReferences"]
  if ! (@options[:app] == 'ffplay' || @options[:app] == 'ffmpeg')
    streams = allStreams.select{|stream| stream["playerType"] == "flash"}
  else
    streams = allStreams
  end
  streams.sort!{|a,b| a["bitrate"] <=> b["bitrate"] }

  def getStreamIndex( streams )
    puts "%2s  %-8s\t%-60s%s" % [ '#', 'Bitrate', 'Stream Name', 'Type' ]
    count = 1
    streams.each{|stream|
                puts "%2d.%10s\t%-60s%s" % [ count, "#{stream["bitrate"]} kbps", stream["url"].sub( /^.*\//,""), stream["playerType"] ]
		count += 1 }
    print "\nWhich file do you want? [#] "
    Integer( gets ) -1
  end
  
  if streams.length == 1
    index = 0
  else
    index = streams.index{|stream| stream["bitrate"]  == @options[:bitrate]}
  end
  
  until (0...streams.length ) === index
    index = getStreamIndex streams
  end
  
  case streams[index]["playerType"]
  when 'ios'
    url = streams[index]["url"].sub( %r{^[^:]+://},"applehttp://")
  when 'wmv'
    url = streams[index]["url"].sub( %r{^[^:]+://},"mmsh://")
  else
    url = streams[index]["url"]
  end
  
  if @options[:extension].empty?
     extension = url[/\.[^\.]+$/]   
  else
    extension = '.' + @options[:extension]
  end
  
  baseFileName = "#{program} #{episod}".strip.tr(' ', '_')
  subtitlesUrl = subtitlesList.first['url'] unless subtitlesList.first.nil?
  
  def execCmd( cmd )
    if @options[:silent] && ( ! @options[:debug] )
	system("#{cmd} > /dev/null 2>&1")
    else
	puts cmd
	system(cmd) unless @options[:debug]
    end    
  end
  
  def verifyFileName( fileName )
    if FileTest.file? fileName
      postfix = fileName[/\.[^\.]+$/]
      newFileName = fileName.sub(/\.[^\.]+$/,"") + "_new" + postfix
      if ! @options[:silent]
	puts "The file #{fileName} exists already!"
	print "Do you want to overwrite? [y/N] "
	overwrite = gets.chomp
	if ! ( overwrite.downcase == 'y' )
	  print "Use new file name #{newFileName}? [other file name] "
	  otherFileName = gets.chomp
	  newFileName = otherFileName unless otherFileName.empty?
	else
	  newFileName = fileName
        end
      end
    else
      newFileName = fileName
    end
    return newFileName
  end
  
  if @options[:subtitles] && !(subtitlesUrl.nil? || subtitlesUrl.empty?)
    subtitlesExtension = '.srt'
    subtitles = verifyFileName "#{baseFileName}#{subtitlesExtension}"
    subCmd = "curl #{subtitlesUrl} -o #{subtitles}"
    execCmd subCmd
  else
    subtitles = ''
  end
  
  case @options[:app]
  when 'rtmpdump'
    outFileName = verifyFileName "#{baseFileName}#{extension}"
    if url =~ %r{^http[s]?://}
      cmd = "curl #{url} -o #{outFileName} #{@options[:xargs]}"
    else
      cmd = "rtmpdump -r #{url} -W #{player} -o #{outFileName} #{@options[:xargs]}"
    end
  when 'ffplay'
    cmd = "ffplay #{@options[:xargs]}"
    if url =~ %r{^rtmp([est]|te)?://}
      cmd += " '#{url} swfUrl=#{player} swfVfy=1'"
    else
      cmd += " #{url}"
    end
  when 'ffmpeg'
    outFileName = verifyFileName "#{baseFileName}#{extension}"
    if @options[:xargs].empty?
       xargs = '-acodec copy -vcodec copy'     
    else
      xargs = @options[:xargs]
    end
    if url =~ %r{^rtmp([est]|te)?://}
      input = "'#{url} swfUrl=#{player} swfVfy=1'"
    else
      input = url
    end
    cmd = "ffmpeg -i #{input} #{xargs} #{outFileName}" 
  end

  execCmd cmd

else
  puts "You must supply a SVT play URL..."
  puts optparse
  exit
end
