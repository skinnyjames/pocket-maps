require_relative "./map/ai/cgi"
require_relative "./map/ai/fake_gps"
require_relative "./map/ai/route_progress"
require_relative "./map/error"
require_relative "./map/geo"
require_relative "./map/geometry"
require_relative "./map/layers"
require_relative "./map/ai/routing"
require_relative "./map/control"
require_relative "./config"
require_relative "./map/controls/search"
require_relative "./map/controls/zoom"
require_relative "./map/controls/banner"

module HackOS
  class Map < Hokusai::Block
    template <<~EOF
    [template]
      vblock
        slot
    EOF

    uses(vblock: Hokusai::Blocks::Vblock)

    inject :control

    def before_updated
      if control.center_changed
        control.update_bounds!
        control.center_changed = false
      end
    end

    def on_resize(canvas)
      control.resize canvas
    end

    def render(canvas)
      on_resize(canvas) if control.bounds_size.nil?

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
    label {
      color: rgb(255,255,255);
    }
    zstyle {
      z: 2;
      ztarget: "parent";
      reverse: true;
    }
    currentLocation {
      height: 30.0;
      background: rgb(22, 22, 22);
      padding: padding(5.0, 5.0, 5.0, 5.0);
    }
    currentLocationText {
      size: 20;
      color: rgb(255,255,255);
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
        :center="control.center"
        :zoom="control.zoom"
      }
        tile_layer { ...tileStyle }
        [if="route"]
          geojson_layer { :data="route" }
      arrival { :height="120.0" }
      [if="current_address"]
        vblock { ...currentLocation :height="current_address_height" }
          text { :content="current_address" ...currentLocationText @height_updated="set_current_address_height" }
    hblock { ...zstyle }
      [if="driving"]
        banner
      [else]
        search
  EOF

  uses(
    arrival: HackOS::ArrivalBar,
    banner: HackOS::Banner,
    dynamic: Hokusai::Blocks::Dynamic,
    text: Hokusai::Blocks::Text,
    search: HackOS::Controls::Search,
    zoom: HackOS::Controls::Zoom,
    icon: Hokusai::Blocks::Icon,
    selectable: Hokusai::Blocks::Selectable,
    hblock: Hokusai::Blocks::Hblock,
    vblock: Hokusai::Blocks::Vblock,
    label: Hokusai::Blocks::Label,
    input: Hokusai::Blocks::Input,
    empty: Hokusai::Blocks::Empty,
    button: Hokusai::Blocks::Button,
    map: HackOS::Map,
    tile_layer: HackOS::TileLayer,
    geojson_layer: HackOS::Maps::GeoJSONLayer,
    marker_layer: HackOS::MarkerLayer
  )

  attr_reader :drag_offset, :update_center
  attr_reader :control, :current_address_height
  provide :control, :control

  def initialize(**args)
    @control = HackOS::Control.new(HackOS::LatLng.new(39.9612, -82.9988))
    @current_address_height = 30.0 + 10.0
    super
  end

  def driving
    !control.progress_geojson.nil?
  end

  def set_current_address_height(height)
    @current_address_height = height + 10.0
  end

  def route
    control.progress_geojson
  end

  def current_address
    control.errors[:current] || control.search_from
  end

  def announce(info, speed)
    m = info[:next_maneuver]
    d = info[:to_next_m]
    return unless m && d

    key = m["begin_shape_index"]
    secs = speed > 1 ? d / speed : Float::INFINITY

    # just finished a turn: say what comes next
    cur = info[:maneuver]
    if cur && !@announced[[cur["begin_shape_index"], :post]]
      @announced[[cur["begin_shape_index"], :post]] = true
      say(cur["verbal_post_transition_instruction"])
    end

    # heads-up
    if secs < 30 && !@announced[[key, :alert]]
      @announced[[key, :alert]] = true
      say(m["verbal_transition_alert_instruction"])
    end

    # right before the turn; short version if we're nearly there
    if secs < 8 && !@announced[[key, :now]]
      @announced[[key, :now]] = true
      say(secs < 4 ? m["verbal_succinct_transition_instruction"] : m["verbal_pre_transition_instruction"])

      # "Then ..." already covered the next turn
      if m["verbal_multi_cue"]
        idx = @progress.maneuvers.index(m)
        following = idx && @progress.maneuvers[idx + 1]
        @announced[[following["begin_shape_index"], :alert]] = true if following
      end
    end
  end

  def target_zoom(info, speed)
    base = speed > 22 ? 5 : (speed > 13 ? 8 : 10)   # highway / arterial / city
    d = info[:to_next_m] || Float::INFINITY

    if d < 120
      @zoomed_in = true
    elsif d > 250
      @zoomed_in = false
    end

    @zoomed_in ? [base + 1, 9].min : base
  end

  def say(text)
    Hokusai.speak(text) if text && !text.empty?
  end

  def render(canvas)
    @announced ||= {}
    control.canvas = canvas
    if info = control.progress      
      control.center = info[:snapped]
      control.update_progress(info)
      announce(info, 43)
    end
    yield canvas
  end
end

require_relative "./icon"

Hokusai::Backend.run(App) do |config|
  config.title = "Hokusai Maps"
  config.fps = 60
  config.width = 500
  config.height = 800
  config.event_waiting = false
  config.audio = true
  config.speech = true

  config.after_load do
    Hokusai.fonts.register "inter", Hokusai::Backend::Font.from_ext(TrollioConfig.asset("Inter-Regular.ttf"), 44)
    Hokusai.fonts.activate "inter"

    Hokusai.fonts.register "icons", Hokusai::Backend::Font.from_ext("assets/material.ttf", 34 * 4, Hokusai::Blocks::Icon::MAP.values.join(""))
  end
end
