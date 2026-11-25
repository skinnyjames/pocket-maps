class Hokusai::Blocks::Icon < Hokusai::Block
  template <<~EOF
  [template]
    virtual
  EOF

  MAP = {
    # navigation
    nav_start: "\u{F0390}",          # navigation
    nav_straight: "\u{F005D}",       # arrow-up
    nav_slight_right: "\u{F005C}",   # arrow-top-right
    nav_slight_left: "\u{F005B}",    # arrow-top-left
    nav_right: "\u{F17AB}",          # arrow-right-top
    nav_left: "\u{F17A7}",           # arrow-left-top
    nav_sharp_right: "\u{F17A9}",    # arrow-right-bottom
    nav_sharp_left: "\u{F17A5}",     # arrow-left-bottom
    nav_uturn_right: "\u{F17B7}",    # arrow-u-right-top
    nav_uturn_left: "\u{F17B3}",     # arrow-u-left-top
    nav_merge: "\u{F00F8}",          # call-merge
    nav_fork: "\u{F09BB}",           # arrow-decision
    nav_roundabout: "\u{F0465}",     # rotate-left (US roundabouts go counterclockwise)
    nav_ferry: "\u{F0213}",          # ferry
    nav_destination: "\u{F023C}",    # flag-checkered
    # general
    magnify: "\u{F0349}",
    return: "\u{F0311}",
    symbol: "\u{F1501}",
    arrowleft: "\u{F004D}",
    arrowright: "\u{F0054}",
    alpha: "\u{F100D}",
    numeric: "\u{F03A0}",
    spacebar: "\u{F1050}",
    deleteleft: "\u{F006E}",
    closecircle: "\u{F0159}",
    exittoapp: "\u{F0206}",
    shift: "\u{F0636}",
    save: "\u{F0193}",
    # phone
    send: "\u{F048A}",
    account_plus: "\u{F0014}",
    phone: "\u{F03F2}",
    phone_hangup: "\u{F03F5}",
    phone_ring: "\u{F11AB}",
    phone_both: "\u{F1B3F}",
    phone_incoming: "\u{F03F7}",
    phone_outgoing: "\u{F03FB}",
    phone_check: "\u{F11A9}",
    phone_pause: "\u{F03FC}",
    phone_classic: "\u{F0602}",
    phone_classic_off: "\u{F1279}",
    # phone app
    microphone: "\u{F036C}",
    contact: "\u{F0006}",
    dialpad: "\u{F061C}",
    home: "\u{F02DC}",
    voicemail: "\u{F057D}",
    history: "\u{F02DA}",
    # technical
    wifi: "\u{F05A9}",
    wifi_alert: "\u{F16B5}",
    # battery
    battery_10: "\u{F007A}",
    battery_20: "\u{F007B}",
    battery_30: "\u{F007C}",
    battery_40: "\u{F007D}",
    battery_50: "\u{F007E}",
    battery_60: "\u{F007F}",
    battery_70: "\u{F0080}",
    battery_80: "\u{F0081}",
    battery_90: "\u{F0082}",
    battery_100: "\u{F0079}",
    # weather
    cloud: "\u{F0590}",
    smog: "\u{F0591}",
    cloud_bolt: "\u{F0593}",
    moon: "\u{F0594}",
    moon_cloud: "\u{F0F31}",
    moon_cloud_rain: "\u{F0597}",
    cloud_rain: "\u{F0597}",
    cloud_meatball: "\u{F0595}",
    snowflake: "\u{F0598}",
    snowman: "\u{F0F36}",
    sun: "\u{F0599}",
    cloud_sun: "\u{F0595}",
    cloud_sun_rain: "\u{F0F33}",
    tornado: "\u{F0F38}",
    cloud_showers_heavy: "\u{F0596}",
    cloud_showers_water: "\u{F0596}",
    directions: "\u{F01D0}",
  }

  computed! :type
  computed :content, default: nil
  computed :size, default: 15, convert: proc(&:to_i)
  computed :color, default: Hokusai::Color.new(0, 0, 0), convert: Hokusai::Color
  computed :background, default: Hokusai::Color.new(255, 255, 255, 0), convert: Hokusai::Color
  computed :outline, default: Hokusai::Outline.default, convert: Hokusai::Outline
  computed :outline_color, default: Hokusai::Color.new(0, 0, 0, 0), convert: Hokusai::Color
  computed :padding, default: Hokusai::Padding.new(2.5, 5.0, 2.5, 5.0), convert: Hokusai::Padding
  computed :center, default: true

  def get_icon_from_type
    icon = MAP[type.to_sym]
    
    raise("No icon #{type}") if icon.nil?

    icon
  end

  def center_in(canvas, size)
    x = canvas.x + (canvas.width / 2.0) - ((size / 2) || 0.0)
    y = canvas.y + (canvas.height / 2.0) - ((size / 2) || 0.0)

    [x, y]
  end

  def render(canvas)
    if Hokusai.fonts.get("icons")
      draw do
        rect(canvas.x, canvas.y, canvas.width, canvas.height) do |command|
          command.color = background
          command.outline = outline
          command.outline_color = outline_color
        end

        x, y = center ? center_in(canvas, size) : [canvas.x, canvas.y]

        text(get_icon_from_type, x, y) do |command|
          command.padding = padding
          command.font = Hokusai.fonts.get("icons")
          command.size = size
          command.color = color
        end

        if content
          text(content, x + size + 15.0, y) do |command|
            command.size = size
            command.color = color
          end
        end
      end

      yield canvas
    end
  end
end