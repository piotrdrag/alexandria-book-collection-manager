# Copyright (C) 2004 Laurent Sansonetti
#
# Alexandria is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# Alexandria is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with Alexandria; see the file COPYING.  If not,
# write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
# Boston, MA 02111-1307, USA.

require 'gconf2'
require 'singleton'

module Alexandria
    class Preferences
        include Singleton
        
        APP_DIR = "/apps/alexandria/"
        WWW_DIR = "/desktop/gnome/url-handlers/http/"

        def initialize
            @client = GConf::Client.new
        end

        def method_missing(id, *args)
            method = id.id2name
            if match = /(.*)=$/.match(method)
                if args.length != 1
                    raise "Set method #{method} should be called with " +
                          "only one argument (was called with #{args.length})"
                end
                @client[APP_DIR + match[1]] = args.first
            else
                unless args.empty?
                    raise "Get method #{method} should be called " +
                          "without argument (was called with #{args.length})"
                end
                @client[APP_DIR + method]
            end                
        end

        def www_browser
            @client[WWW_DIR + "command"] if @client[WWW_DIR + "enabled"]
        end
    end
end