module HackOS
  class TileLayer < Hokusai::Block
    MAX_IN_FLIGHT = 40
    RETRY_AFTER   = 15    # seconds, assuming Hokusai.monotonic is in seconds
    MAX_CACHED    = 2000  # files kept in ./downloads

    template <<~EOF
    [template]
      empty {
        @mousedown="start_drag"
        @mousemove="drag"
        @mouseup="end_drag"
      }
    EOF

    uses(
      empty: Hokusai::Blocks::Empty
    )

    computed! :url
    computed :tile_size, default: 256, convert: proc(&:to_i)
    computed :min_zoom, default: 0, convert: proc(&:to_i)
    computed :max_zoom, default: 18, convert: proc(&:to_i)
    computed :subdomains, default: ['a', 'b', 'c']
    computed :zoom_offset, default: 9, convert: proc(&:to_i)
    computed :zoom_reverse, default: false

    inject :control

    attr_reader :tiles, :dragging

    job :save_tile do |state|
      src = state[:src] || state["src"]
      dst = state[:dst] || state["dst"]

      ok = false
      begin
        File.open(src, "r") do |i|
          File.open(dst, "wb") do |o|
            while (chunk = i.read(65536))
              break if chunk.empty?
              o << chunk
            end
          end
        end
        ok = true
      rescue => e
        File.delete(dst) if File.exist?(dst)   # don't leave a partial file that looks cached
      ensure
        File.delete(src) if File.exist?(src)
      end

      { ok: ok }
    end

    def initialize(**args)
      super

      @requests = {}
      @tiles = {}
      @pending = {}
      @queued = {}
      @failed = {}
      @in_flight = 0
      @pruned = false
      @dragging = false
      @drag_start = nil
    end

    def acquire(origin)
      pool = (@requests[origin] ||= [])
      conn = pool.find { |c| !c[:busy] }
      unless conn
        conn = { req: Hokusai::Request.init(self, origin), busy: false }
        pool << conn
      end
      conn[:busy] = true
      conn
    end

    # --- dragging ---

    def start_drag(event)
      if !@dragging && event.left.down
        @dragging = true
        @drag_start = Point.new(event.pos.x, event.pos.y)
      end
    end

    def drag(event)
      if event.left.down && dragging
        control.bounds.drag_offset = Point.new(event.pos.x, event.pos.y) - @drag_start
      end
    end

    def end_drag(event)
      return unless dragging && event.left.up

      @dragging = false
      off = control.bounds.drag_offset

      if off.x.abs > 5 || off.y.abs > 5
        center = control.bounds.coords_at(control.bounds.screen_bounds.center, control.zoom)

        control.bounds.drag_offset = Point.new(0, 0)
        control.bounds.center = center
        control.center = center
      end

      @drag_start = nil
    end

    # --- urls ---

    def downloads
      "./downloads"
    end

    def headers
      {
        "Referer" => "skinnyjames.net",
        "Referrer-Policy" => "strict-origin-when-cross-origin",
        "User-Agent" => "Hokusai/1.4 (+https://hokusai.skinnyjames.net; contact: zero@skinnyjames.net)"
      }
    end

    def safe_name(url)
      url.gsub(/[^A-Za-z0-9._-]/, "_")
    end

    def subdomain(coords)
      subdomains[(coords.x.to_i + coords.y.to_i) % subdomains.size]
    end

    def zoom_for_url
      zoom_reverse ? max_zoom - control.zoom : control.zoom + zoom_offset
    end

    # https://{s}.somedomain.com/blabla/{z}/{x}/{y}{r}.png
    def tile_url(coords)
      opts = {
        s: subdomain(coords),
        z: zoom_for_url,
        x: coords.x.to_i,
        y: coords.y.to_i,
        r: ''
      }

      url.gsub(/\{ *([\w_ -]+) *\}/) do |match|
        opts[match[1].to_sym].to_s
      end
    end

    def request_for(origin)
      @requests[origin] ||= Hokusai::Request.init(self, origin)
    end

    def split_url(tile)
      i = tile.index("/", tile.index("://") + 3)
      [tile[0...i], tile[i..-1]]   # ["https://tile.openstreetmap.org", "/9/137/193.png"]
    end

    # --- downloading ---

    # Returns the tile image if ready, otherwise nil (and queues it if needed).
    def fetch_download(tile)
      return @tiles[tile] if @tiles[tile]
      return nil if @pending[tile]

      if (failed_at = @failed[tile])
        return nil if Hokusai.monotonic - failed_at < RETRY_AFTER
        @failed.delete(tile)
      end

      path = "#{downloads}/#{safe_name(tile)}"

      if File.exist?(path)
        begin
          return @tiles[tile] = Hokusai::Image.from_file(path)
        rescue => e
          @failed[tile] = Hokusai.monotonic
          return nil
        end
      end

      @queued[tile] ||= path
      nil
    end

    # Drop queued tiles that scrolled away, then start up to the cap.
    def pump(wanted)
      @queued.keys.each { |u| @queued.delete(u) unless wanted[u] }

      while @in_flight < MAX_IN_FLIGHT && (tile = @queued.keys.first)
        start_download(tile, @queued.delete(tile))
      end
    end

    def start_download(tile, path)
      @pending[tile] = true
      @in_flight += 1
      origin, req_path = split_url(tile)
      conn = acquire(origin)
      
      conn[:req].execute(req_path, { method: "GET", headers: headers }) do |res|
        if res.code == 200
          run :save_tile, { src: res.body.tmp, dst: path } do |r|
            begin
              if r[:ok] || r["ok"]
                @tiles[tile] = Hokusai::Image.from_file(path)
              else
                @failed[tile] = Hokusai.monotonic
              end
            ensure
              @pending.delete(tile)
              @in_flight -= 1
              conn[:busy] = false
            end
          end
        else
          @failed[tile] = Hokusai.monotonic
          @pending.delete(tile)
          @in_flight -= 1
          conn[:busy] = false
        end
      end
    end

    # --- cache pruning (worker) ---

    # def prune_once
    #   return if @pruned
    #   @pruned = true

    #   run :prune_cache, { dir: downloads, max: MAX_CACHED } do |result|
    #     p ["pruned", result]
    #   end
    # end

    # --- rendering ---

    def render(canvas)
      # prune_once

      collection = control.bounds.collection(control.zoom)
      offx = collection.offset.x
      offy = collection.offset.y

      items = []
      wanted = {}

      collection.each_with_index do |item, _i|
        tile = tile_url(item.map.center)
        wanted[tile] = true
        items << [item, tile]
      end

      items.each { |_, tile| fetch_download(tile) }
      pump(wanted)

      draw do
        items.each do |item, tile|
          if (file = @tiles[tile])
            image(
              file,
              item.screen.center.x - offx.to_f,
              item.screen.center.y - offy.to_f,
              tile_size.to_f,
              tile_size.to_f
            ) {}
          end
        end
      end

      yield canvas
    end
  end
end