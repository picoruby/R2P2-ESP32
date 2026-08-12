desc "Generate storage/etc/network/wifi.yml for WiFi auto-connect"
task :gen_wifi_config do
  require 'openssl'
  require 'base64'
  require 'yaml'

  ssid      = ENV['SSID']      or abort "SSID is required. Usage: rake gen_wifi_config SSID=... PASSWORD=... UNIQUE_ID=..."
  password  = ENV['PASSWORD']  or abort "PASSWORD is required."
  unique_id = ENV['UNIQUE_ID'] or abort "UNIQUE_ID is required. Get it from Machine.unique_id on the device."

  # AES-256-CBC encryption (same as wifi_connect.rb decrypt logic)
  key_len = 32
  iv_len  = 16
  len = unique_id.length
  key = (unique_id * ((key_len / len + 1) * len))[0, key_len]
  iv  = (unique_id * ((iv_len  / len + 1) * len))[0, iv_len]

  cipher = OpenSSL::Cipher.new('AES-256-CBC')
  cipher.encrypt
  cipher.key = key
  cipher.iv  = iv
  ciphertext = cipher.update(password) + cipher.final

  encoded_password = Base64.strict_encode64(ciphertext)

  doc = {
    'wifi' => {
      'ssid' => ssid,
      'encoded_password' =>  encoded_password,
      'auto_connect' => (ENV.fetch('AUTO_CONNECT', 'true') == 'true'),
      'retry_if_failed' => (ENV.fetch('RETRY_IF_FAILED', 'true') == 'true'),
      'watchdog' => (ENV.fetch('WATCHDOG', 'false') == 'true')
    }
  }
  doc['country_code'] = ENV['COUNTRY_CODE'] if ENV['COUNTRY_CODE']

  output_path = File.join(R2P2_ESP32_ROOT, "storage/etc/network/wifi.yml")
  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, YAML.dump(doc).sub(/\A---\s*\n/, ''))
  puts "Generated: #{output_path}"
end
