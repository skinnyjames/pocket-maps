
require_relative "./map/error"
require_relative "./map/geo"
require_relative "./map/layers"
require_relative "./map/geometry"
require_relative "./map/control"
require_relative "./config"

module HackOS
  class Map < Hokusai::Block
    template <<~EOF
    [template]
      vblock
        slot
    EOF

    uses(vblock: Hokusai::Blocks::Vblock)

    attr_reader :size
    attr_accessor :sdrag
  
    provide :zoom, :zoom
    provide :center, :center
    provide :container_size, :size
    provide :tile_bounds, :tile_bounds

    computed! :center
    computed :crs, default: "EPSG3857"
    computed :zoom, default: 1
    computed :min_zoom, default: nil
    computed :max_zoom, default: nil
    computed :update_center, default: nil

    def before_updated
      if update_center
        @bounds = TileBounds.new(HackOS::EPSG3857, update_center, size)
        emit("clear_update_center")
      end
    end

    def start_drag(event)
              p event.pos.x, event.pos.y

      if event.left.down && !@started
        self.sdrag = [event.pos.x.clone, event.pos.y.clone]
        @started = true
      end
    end

    def on_resize(canvas)
      @size = Bounds.new([canvas.x, canvas.y], [canvas.x + canvas.width, canvas.y + canvas.height])
      @bounds = TileBounds.new(HackOS::EPSG3857, center, size)
    end

    def center_point
      HackOS::EPSG3857.lat_lng_to_point(center, zoom)
    end

    def alert_latlng(event)
      if sdrag && ((event.pos.x - sdrag[0]).abs > 5 || (event.pos.y - sdrag[1]).abs > 5)
        @started = false
        self.sdrag = nil
        return
      end
    
      if event.left.released
        point = Point.new(event.pos.x, event.pos.y)
        clicked = Point.new(event.pos.x, event.pos.y)
        emit("change", tile_bounds.coords_at(point, zoom), clicked)
        @started = false
      end
    end

    def tile_bounds
      @bounds ||= TileBounds.new(HackOS::EPSG3857, center, size)
    end

    def render(canvas)
      if @size.nil?
        on_resize(canvas)
      end

      yield canvas
    end
  end
end

class App < Hokusai::Block
  style <<~EOF
  [style]
    tileStyle {
      url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
      zoom_offset: 8;
    }
    box {
      background: rgb(48, 48, 48);
      height: 100.0;
      padding: padding(20.0, 0.0, 30.0, 0.0);
    }

    input {
      background: rgb(255,255,255);
      color: rgb(22,22,22);
      padding: padding(5.0, 15.0, 5.0, 15.0);
      outline: outline(1.0, 1.0, 1.0, 1.0)
      outline_color: rgb(33,33,33);
      height: 50.0;
      rounding: 0.2;
    }

    label {
      color: rgb(255,255,255);
    }

    zstyle {
      z: 2;
      ztarget: "parent";
      reverse: true;
    }
  EOF

  template <<~EOF
  [template]
    vblock
      map {
        @change="update_latlng"
        @clear_update_center="clear_update_center"
        :update_center="update_center"
        cursor="pointer"
        :center="center"
        :zoom="zoom"
      }
        tile_layer {
          ...tileStyle 
        }
        marker_layer {:marker="marker"}
    hblock { ...zstyle }
      control { 
        @zoomin="zoom_in"
        @zoomout="zoom_out"
        :height="80.0" :width="65.0"
      }
      empty
      vblock { padding="10.0,0.0,0.0,10.0"}
        input { @mousedown="stop" model="foo" @change="search" ...input }
  EOF

  uses(
    hblock: Hokusai::Blocks::Hblock,
    vblock: Hokusai::Blocks::Vblock,
    label: Hokusai::Blocks::Label,
    input: Hokusai::Blocks::Input,
    empty: Hokusai::Blocks::Empty,
    control: HackOS::Control,
    button: Hokusai::Blocks::Button,
    map: HackOS::Map,
    tile_layer: HackOS::TileLayer,
    marker_layer: HackOS::MarkerLayer
  )

  attr_reader :drag_offset, :update_center

  def on_mounted
    p ["mount"]
  end

  def stop(event)
    event.stop
  end

  def point
    @point || "no point"
  end

  def initialize(**args)
    super

    @dragging = false
  end

  def marker
    @marker
  end

  def search(term)
    begin
      fetch("https://geoffrey.skinnyjames.net/api/v1/us/geocode/#{CGI.escapeURIComponent(term)}", { "method" => "GET"}) do |res|
        body = res.body.json
        p body
        @update_center = HackOS::LatLng.new(res["latitude"], res["longitude"])
        @marker = HackOS::Point.new(400, 400)
      end
    end
  end

  def update_latlng(latlng, point)
    p["changing"]
    @marker = point.clone
    add = latlng.reverse_geo
    @point = <<~EOF
    #{latlng}
    #{add[:address_number]} #{add[:street_name]} #{add[:street_posttype]}
    #{add[:postal_community]}, #{add[:state]} #{add[:zip_code]}
    EOF
  end
  
  def clear_update_center
    @update_center = nil
  end

  def zoom_out
    @marker = nil
    @zoom -= 1
  end

  def zoom
    @zoom ||= 1
  end

  def center
    @center ||= HackOS::LatLng.new(39.9612, -82.9988)
  end

  def zoom_in
    @marker = nil

    @zoom += 1
  end
end


Hokusai::Backend.run(App) do |config|
  config.title = "Hokusai Paint"
  config.fps = 60
  config.width = 1400
  config.height = 800
  # config.draw_fps = true
  # config.config_flags = HP_FLAG_WINDOW_RESIZABLE
  # config.log = true
  config.audio = false

  config.after_load do
    Hokusai.fonts.register "inter", Hokusai::Backend::Font.from(TrollioConfig.asset("Inter-Regular.ttf"))
    Hokusai.fonts.activate "inter"
  end
end


# Hokusai::Backend.run(App) do |config|
#   config.title = "Trollio Maps"
#   config.width = 800
#   config.height = 800

#   config.after_load do
#     Hokusai.fonts.register "inter", Hokusai::Backend::Font.from(TrollioConfig.asset("Inter-Regular.ttf"))
#     Hokusai.fonts.activate "inter"
#     Hokusai.maximize_window
#   end
# end


#
# 1 = 9
# 2 = 10
# 3 = 11
#
#

# latlng = HackOS::LatLng.new(39.9612, -82.9988)
# point = HackOS::EPSG3857.lat_lng_to_point(latlng, 4)
# new_lat_lng = HackOS::EPSG3857.point_to_lat_lng(point, 4)

# map = HackOS::EPSG3857

# pmap.projection.project(map.projection.unproject(HackOS::Point.new(0, 0)))
