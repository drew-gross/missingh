{- arch-tag: FTP server support
Copyright (C) 2004 John Goerzen <jgoerzen@complete.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- |
   Module     : MissingH.Network.FTP.Server
   Copyright  : Copyright (C) 2004 John Goerzen
   License    : GNU GPL, version 2 or above

   Maintainer : John Goerzen, 
   Maintainer : jgoerzen@complete.org
   Stability  : experimental
   Portability: systems with networking

This module provides a server-side interface to the File Transfer Protocol
as defined by RFC959 and RFC1123.

Written by John Goerzen, jgoerzen\@complete.org

-}

module MissingH.Network.FTP.Server(
                                   ftpHandler
                                  )
where
import MissingH.Network.FTP.ParserServer
import Network.BSD
import Network.Socket
import qualified Network
import System.IO
import MissingH.Logging.Logger
import MissingH.Network
import MissingH.Str
import MissingH.Printf
import MissingH.IO.HVIO
import Data.Char
import MissingH.Printf

s_crlf = "\r\n"
ftpPutStrLn :: Handle -> String -> IO ()
ftpPutStrLn h text =
    do hPutStr h (text ++ s_crlf)
       hFlush h

{- | Send a reply code, handling multi-line text as necessary. -}
sendReply :: Handle -> Int -> String -> IO ()
sendReply h codei text =
    let codes = vsprintf "%03d" codei
        writethis [] = ftpPutStrLn h (codes ++ "  ")
        writethis [item] = ftpPutStrLn h (codes ++ " " ++ item)
        writethis (item:xs) = do ftpPutStrLn h (codes ++ "-" ++ item)
                                 writethis xs
        in 
        writethis (map (rstrip) (lines text))

{- | Main FTP handler; pass this to 
'MissingH.Network.SocketServer.handleHandler' -}

ftpHandler :: Handle -> SockAddr -> IO ()
ftpHandler h sa =
    traplogging "MissingH.Network.FTP.Server" NOTICE "" $
       do sendReply h 220 "Welcome to MissingH.Network.FTP.Server."
          commandLoop h sa

type CommandHandler = Handle -> SockAddr -> String -> IO Bool

commands :: [(String, (CommandHandler, (String, String)))]
commands =
    [("HELP", (cmd_help, help_help))
    ]

commandLoop :: Handle -> SockAddr -> IO ()
commandLoop h sa =
    let errorhandler e = do noticeM "MissingH.Network.FTP.Server"
                                    ("Closing due to error: " ++ (show e))
                            hClose h
                            return False
        in do continue <- (flip catch) errorhandler 
               (do x <- parseCommand h
                   case x of
                     Left err -> do sendReply h 500 $
                                      "Couldn't parse command: " ++ (show err)
                                    return True
                     Right (cmd, args) -> 
                         case lookup cmd commands of
                            Nothing -> do sendReply h 500 $
                                           "Unrecognized command " ++ cmd
                                          return True
                            Just hdlr -> (fst hdlr) h sa args
               )
              if continue
                 then commandLoop h sa
                 else return ()

help_help =
    ("Display help on available commands",
     "When called without arguments, shows a summary of available system\n"
     ++ "commands.  When called with an argument, shows detailed information\n"
     ++ "on that specific command.")

cmd_help :: CommandHandler
cmd_help h sa args =
    let genericreply addr = unlines $
          ["Welcome to the FTP server, " ++ addr ++ "."
          ,"This server is implemented as the MissingH.Network.FTP.Server"
          ,"component of the MissingH library.  The MissingH library"
          ,"is available from http://quux.org/devel/missingh."
          ,""
          ,""
          ,"I know of the following commands:"
          ,concatMap (\ (name, (_, (summary, _))) -> vsprintf "%-10s %s\n" name summary)
              commands
          ,""
          ,"You may type \"HELP command\" for more help on a specific command."
          ]
        in
        if args == ""
           then do sastr <- showSockAddr sa
                   sendReply h 214 (genericreply sastr)
                   return True
           else let newargs = map toUpper args
                    in case lookup newargs commands of
                         Nothing -> do 
                                    sendReply h 214 $ "No help for \"" ++ newargs
                                      ++ "\" is available.\nPlese send HELP"
                                      ++ " without arguments for a list of\n"
                                      ++ "valid commands."
                                    return True
                         Just (_, (summary, detail)) ->
                             do sendReply h 214 $ newargs ++ ": " ++ summary ++ 
                                               "\n\n" ++ detail
                                return True