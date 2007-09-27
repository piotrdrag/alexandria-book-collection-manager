# -*- Mode: ruby; ruby-indent-level: 4 -*-
#
# Copyright (C) 2004-2006 Laurent Sansonetti
# Copyright (C) 2007 Cathal Mc Ginley
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

require 'alexandria/scanners/cuecat'

module Alexandria
module UI
    class AcquireDialog < GladeBase
        include GetText
        extend GetText
        GetText.bindtextdomain(Alexandria::TEXTDOMAIN, nil, nil, "UTF-8")

        def initialize(parent, selected_library=nil, &block)
            super('acquire_dialog.glade')
            @acquire_dialog.transient_for = @parent = parent
            @block = block

            libraries = Libraries.instance.all_regular_libraries
            if selected_library.is_a?(SmartLibrary)
                selected_library = libraries.first
            end
            @combo_libraries.populate_with_libraries(libraries,
                                                     selected_library)

            @add_button.sensitive = false
            setup_scanner_area
            init_treeview
            @book_results = Hash.new
        end

        def on_add
            model = @barcodes_treeview.model
            selection = @barcodes_treeview.selection
            isbns = []
            if selection.count_selected_rows > 0
                model.freeze_notify do
                    # capture isbns
                    selection.selected_each do |model, path, iter|
                        isbns << iter[0]
                    end
                    # remove list items (complex, cf. tutorial...)
                    # http://ruby-gnome2.sourceforge.jp/hiki.cgi?tut-treeview-model-remove
                    #row_refs = []
                    #paths = selection.selected_rows
                    #paths.each do |path|
                    #    row_refs << Gtk::TreeRowReference.new(model, path)
                    #end
                    #row_refs.each do |ref|
                    #    model.remove(model.get_iter(ref.path))
                    #end

                    # try it this way... works because of persistent iters
                    row_iters = []
                    selection.selected_rows.each do |path|
                        row_iters << model.get_iter(path)
                    end
                    row_iters.each do |iter|
                        model.remove(iter)
                    end

                end
            else
                model.freeze_notify do
                    # capture isbns
                    model.each do |model, path, iter|
                        isbns << iter[0]
                    end
                    # remove list items
                    model.clear
                end
            end

            libraries = Libraries.instance.all_libraries
            library, new_library =
                @combo_libraries.selection_from_libraries(libraries)
            isbns.each do |isbn|
                puts "Adding #{isbn}"
                result = @book_results[isbn]
                book = result[0]
                cover_uri = result[1]

                unless cover_uri.nil?
                    library.save_cover(book, cover_uri)
                end
                library << book
                library.save(book)
            end
        end

        def on_cancel
            @acquire_dialog.destroy
        end

        def on_help
        end

        def read_barcode_scan
            puts "reading CueCat data #{@scanner_buffer}"
            barcode_text = nil
            isbn = nil
            begin
                barcode_text = @scanner.decode(@scanner_buffer)
                puts "got barcode text #{barcode_text}"
                isbn = Library.canonicalise_isbn(barcode_text)
                # TODO :: use an AppFacade
                # isbn =  LookupBook.get_isbn(barcode_text)
            rescue StandardError => err
                puts "Bad scan:  #{@scanner_buffer} #{err}"
            ensure
                @scanner_buffer = ""
            end
            if isbn
                puts "<<< #{isbn} >>>"
                # TODO :: sound
                # play_sound("gnometris/turn")

                #t = Thread.new(isbn) do |isbn|
                @barcodes_treeview.model.freeze_notify do
                    iter = @barcodes_treeview.model.append
                    iter[0] = isbn
                    iter[1] = "<<Title>>"
                end
                lookup_book(isbn)
                #end
            else
                puts "was not an ISBN barcode"
                # TODO :: sound
                # play_sound("question")
            end
        end

        private

        def lookup_book(isbn)
            lookup_thread = Thread.new(isbn) do |isbn|
                begin
                    results = Alexandria::BookProviders.isbn_search(isbn)
                    book = results[0]
                    @book_results[isbn] = results
                    @barcodes_treeview.model.freeze_notify do
                        iter = @barcodes_treeview.model.each do |model, path, iter|
                            if iter[0] == isbn
                                iter[1] = book.title
                                model.row_changed(path, iter)
                            end
                        end
                    end
                    @add_button.sensitive = true
                rescue StandardError => err
                    puts err
                end
            end
        end

        def setup_scanner_area
            @scanner_buffer = ""
            @scanner = Alexandria::Scanners::CueCat.new # HACK :: use Registry

            # attach signals
            @scan_area.signal_connect("button-press-event") do |widget, event|
                @scan_area.grab_focus
            end
            @scan_area.signal_connect("focus-in-event") do |widget, event|
                @barcode_label.label = _("_Barcode Scanner Ready")
                @scanner_buffer = ""
                begin
                    # @frame1.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0xEE))
                    # @frame1.modify_bg(Gtk::STATE_ACTIVE, Gdk::Color.new(0, 0, 0xEE))
                    points = [[-100,-10], [300,-10], [300,300], [-100,300]]
                    @scanner_background = Gnome::CanvasPolygon.new(@barcode_canvas.root,
                                          {:points => points, :fill_color_rgba => 0xFDFDFDFF})
                rescue StandardError => err
                    puts err
                end
            end
            @scan_area.signal_connect("focus-out-event") do |widget, event|
                @barcode_label.label = _("Click below to scan _barcodes")
                @scanner_buffer = ""
                @scanner_background.destroy
            end

            @@debug_index = 0
            @scan_area.signal_connect("key-press-event") do |button, event|
                #puts event.keyval
                if event.keyval < 255
                    if @scanner_buffer.empty?
                        if event.keyval.chr == '`' # backtick key for devs
                            developer_test_scan
                            next
                        else
                            # this is our first character, notify user
                            puts "Scanning... "
                        end
                        # TODO :: sound
                        # play_sound("iagno/flip-piece")
                    end
                    @scanner_buffer << event.keyval.chr

                    # or get event.keyval == 65293 meaning Enter key
                    if @scanner.match? @scanner_buffer
                        read_barcode_scan
                    end
                end
            end


            # TODO :: sound
            # Gnome::Sound.init("localhost")

        end

        def developer_test_scan
            puts "Developer test scan..."
            scans = [".C3nZC3nZC3n2ChnWENz7DxnY.cGen.ENr7C3j3C3f1Dxj3Dq.",
                     ".C3nZC3nZC3n2ChnWENz7DxnY.cGen.ENr7C3z0CNj3Dhj1EW.",
                     ".C3nZC3nZC3n2ChnWENz7DxnY.cGen.ENr7C3r2DNbXCxTZCW.",
                     ".C3nZC3nZC3n2ChnWENz7DxnY.cGf2.ENr7C3z0DNn0ENnWE3nZDhP6.",
                     ".C3nZC3nZC3n2ChnWENz7DxnY.cGen.ENr7CNT2CxT2ChP0Dq.",
                     ".C3nZC3nZC3n2ChnWENz7DxnY.cGen.ENr7CNT6E3f7CNbWDa.",
                     ".C3nZC3nZC3n2ChnWENz7DxnY.cGen.ENr7C3b3ENjYDxv3EW.",
                     ".C3nZC3nZC3n2ChnWENz7DxnY.cGen.ENr7C3b2DxjZE3b3Dq.",
                     ".C3nZC3nZC3n2ChnWENz7DxnY.cGen.ENr7C3n6CNr6DxvYDa."]
            @scanner_buffer = scans[@@debug_index % scans.size]
            @@debug_index += 1
            read_barcode_scan
        end

        def init_treeview
            puts 'initializing treeview...'
            liststore = Gtk::ListStore.new(String, String)

            @barcodes_treeview.selection.mode = Gtk::SELECTION_MULTIPLE

            @barcodes_treeview.model = liststore

            text_renderer = Gtk::CellRendererText.new
            text_renderer.editable = false

            # Add column using our renderer
            col = Gtk::TreeViewColumn.new("ISBN", text_renderer, :text => 0)
            @barcodes_treeview.append_column(col)

            # Add column using the second renderer
            col = Gtk::TreeViewColumn.new("Title", text_renderer, :text => 1)
            @barcodes_treeview.append_column(col)


            @barcodes_treeview.model.signal_connect("row-deleted") do |model, path|
                if not model.iter_first
                    @add_button.sensitive = false
                end
            end
        end

        #def play_sound(filename)
        #    dir = "/usr/share/sounds"
        #    Gnome::Sound.play("#{dir}/#{filename}.wav")
        #end

    end
end
end