# Copyright (C) 2004-2006 Pascal Terjan 
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

require 'cgi'
require 'net/http'

module Alexandria
class BookProviders
    class ProxisProvider < GenericProvider
        include GetText
        GetText.bindtextdomain(Alexandria::TEXTDOMAIN, nil, nil, "UTF-8")
        
        LANGUAGES = {
            'nl' => '1',
            'en' => '2',
            'fr' => '3'
        }

        def initialize
            super("Proxis", "Proxis (Belgium)")
            prefs.add("lang", _("Locale"), "fr",
                      LANGUAGES.keys)
        end
        
        def search(criterion, type)
            prefs.read

            criterion = criterion.convert("windows-1252", "UTF-8")
            req = case type
                when SEARCH_BY_ISBN
                    "p_isbn=#{Library.canonicalise_isbn(criterion)}&p_title=&p_author="
          
                when SEARCH_BY_TITLE
                    "p_isbn=&p_title=#{CGI::escape(criterion)}&p_author="
          
                when SEARCH_BY_AUTHORS
                    "p_isbn=&p_title=&p_author=#{CGI::escape(criterion)}"
            
                when SEARCH_BY_KEYWORD
                    "p_isbn=&p_title=&p_author=&p_keyword=#{CGI::escape(criterion)}"
          
                else
                    raise InvalidSearchTypeError

            end
          
            products = {}
            results_page = "http://oas2000.proxis.be/gate/jabba.search.submit_search?#{req}&p_item=#{LANGUAGES[prefs['lang']]}&p_order=1&p_operator=K&p_filter=1"
            transport.get(URI.parse(results_page)).each do |line|
                if line =~ /br>.*DETAILS&mi=([^&]*)&si=/ #and (!products[$1]) and (book = parseBook($1)) then
                    book = parseBook($1)
                    products[$1] = book
                end
            end
            
	    # Workaround Proxis returning all editions of a book when searching on ISBN
	    if type == SEARCH_BY_ISBN 
		    products.delete_if {|n, p| p.first.isbn != Library.canonicalise_ean(criterion)}
	    end
	    
            raise NoResultsError if products.values.empty?
            type == SEARCH_BY_ISBN ? products.values.first : products.values
        end

        def url(book)
            "http://oas2000.proxis.be/gate/jabba.search.submit_search?p_isbn=" + book.isbn + "&p_item=1"
        end

        #######
        private
        #######

        def parseBook(product_id)
            conv = proc { |str| str.convert("UTF-8", "windows-1252") if str != nil }
            detailspage='http://oas2000.proxis.be/gate/jabba.coreii.g_p?bi=4&sp=DETAILS&mi='+product_id
            product = {}
            product['authors'] = []
            nextline = nil
            transport.get(URI.parse(detailspage)).each do |line|
                if line =~ /span class="?AUTHOR"?>([^<]*)&nbsp; &nbsp;/i
                    author = $1.gsub('&nbsp;',' ').sub(/ +$/,'')
                    product['authors'] << author
                elsif line =~ /SRC="(http:\/\/www.proxis.be\/IMG.\/.*)M\.jpg"/i 
                    product['image_url_small'] = $1+'S.jpg'
                    product['image_url_medium'] = $1+'M.jpg'
                    product['image_url_large'] = $1+'L.jpg'
#                elsif line =~ /class="?TITLECOLOR"?>([^<]*)</i 
                elsif line =~ /<tr width="?100%"?><td valign="?middle"? width="?100%"? class="?verd_13_b"?>([^<]*)</i 
                    product['name'] = $1.sub(/ +$/,'')
                elsif line =~ /Barcode \(EAN\)<\/TD><TD class="?INFO"?> : ([^<]*)</i 
                    product['isbn'] = $1
                elsif line =~ /Publication date<\/TD><TD class="?INFO"?> : ..\/..\/([[:digit:]]{4})/i
                    product['year'] = $1.to_i
                elsif line =~ /Type<\/TD>/i
                    nextline = "media"
                elsif line =~ /(Publisher|Editeur|Uitgever)<\/TD><TD CLASS="?INFO"?>: ([^<]*)</i 
                    product['manufacturer'] = $2
                elsif line =~ /TD CLASS="?INFO"?>: ([^<]*)</i and nextline
                    product[nextline] = $1
                end
            end

#            %w{name isbn media manufacturer}.each do |field|
#                product[field] = "" if product[field].nil?
#            end 
            
            book = Book.new(conv.call(product['name']),
                            (product['authors'].map { |x| conv.call(x) } rescue [  ]),
                            conv.call(product['isbn']),
                            conv.call(product['manufacturer']),
                            product['year'],
                            conv.call(product['media']))
        
            return [ book, product['image_url_medium'] ]
        end
    end
end
end
