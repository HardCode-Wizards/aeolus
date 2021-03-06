class Node < ApplicationRecord
  belongs_to :room
  has_many :slots
  has_many :climate_control_units, through: :slots
  has_many :data_points

  validates :room, presence: :true
  validates :api_key,
            presence: :true,
            uniqueness: :true
  validates :capabilities,
            presence: :true,
            inclusion: {
              in: 0..31
            }
  validates_uniqueness_of :outside, if: :outside?

  def decode_capabilities
    decoded_capabilities = []

    if capabilities % 2 == 1
      decoded_capabilities.append('temperature')
    end

    if (capabilities >> 1) % 2 == 1
      decoded_capabilities.append('humidity')
    end

    if (capabilities >> 2) % 2 == 1
      decoded_capabilities.append('ir')
    end

    if (capabilities >> 3) % 2 == 1
      decoded_capabilities.append('voc')
    end

    if (capabilities >> 4) % 2 == 1
      decoded_capabilities.append('control')
    end

    return decoded_capabilities
  end

  def compute_states
    states = {}
    slots.each do |slot|
      states[slot.kind] = 'off'
    end

    if room.enabled?
      outside_node_data_points = Node.find_by(outside: true).try(:data_points)
      outside_temperature = outside_node_data_points.try(:temperature).try(:last).try(:value)
      outside_humidity = outside_node_data_points.try(:humidity).try(:last).try(:value)

      temperature_target = room.targets.temperature.first.try(:value)
      humidity_target = room.targets.humidity.first.try(:value)
      last_temperature = room.data_points.temperature.last.try(:value)
      last_humidity = room.data_points.humidity.last.try(:value)

      if temperature_target && last_temperature
        heating = temperature_target > last_temperature
        cooling = temperature_target < last_temperature
      end

      if humidity_target && last_humidity
        dehumidification = humidity_target < last_humidity
        humidification = humidity_target > last_humidity
      end

      # Use the outside environment as the climate control unit only if we can use
      # it for both the temperature and humidity targets if they are set
      if !climate_control_units.outside.blank? &&
        (heating && outside_temperature > last_temperature ||
        cooling && outside_temperature < last_temperature ||
        !heating && !cooling) &&
        (humidification && outside_humidity > last_humidity ||
        dehumidification && outside_humidity < last_humidity ||
        !humidification && !dehumidification)
        states[climate_control_units.slot.kind] = 'on'
        return states
      end

      if heating
        climate_control_units.heater.each do |ccu|
          states[ccu.slot.kind] = 'on'
        end
      elsif cooling
        climate_control_units.cooler.each do |ccu|
          states[ccu.slot.kind] = 'on'
        end
      end

      if dehumidification
        climate_control_units.dehumidifier.each do |ccu|
          states[ccu.slot.kind] = 'on'
        end
      elsif humidification
        climate_control_units.humidification.each do |ccu|
          states[ccu.slot.kind] = 'on'
        end
      end
    end

    return states
  end
end
