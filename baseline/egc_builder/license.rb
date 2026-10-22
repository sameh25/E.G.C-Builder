# frozen_string_literal: true

require 'json'
require 'base64'
require 'digest'

module EGC
  # Activation keys. A key is issued by the vendor (tools outside this package) for a name, an end date ('YYYY-MM-DD' or 'perpetual')
  # and - optionally - one machine. It is SIGNED with the vendor's private key (Ed25519); this package carries only the PUBLIC key, so
  # a key cannot be made or altered from what is shipped here. Without a valid key the plugin opens (to enter one) but builds nothing.
  # Limits, stated plainly: the package is plain Ruby - someone who edits the source can remove the check. It keeps honest testers to
  # their period; it is not copy protection.
  module License
    ENFORCE = false # OWNER build
    # A TRIAL package carries its own last day ('YYYY-MM-DD', written by tools/pack_trial.ps1 into a temporary copy - never here): after
    # that day this file stops for EVERY key, so a trial copy that is passed on cannot be kept alive with another key.
    BUILD_EXPIRES = nil
    # ... who this package was made for (printed on what it produces, so a copy that travels can be traced) ...
    BUILD_FOR = nil
    # ... and whether it only takes a key issued for ONE computer (a key for 'any computer' is refused, so it cannot be handed on).
    BUILD_NEEDS_MACHINE = false
    PREFIX = 'EGC1'
    PUBLIC_KEY = <<~PEM
      -----BEGIN PUBLIC KEY-----
      MCowBQYDK2VwAyEAKBwkZmwMXHrNL0hQ4yXBN7kZ/6TYL/+fpYIgSjAsflE=
      -----END PUBLIC KEY-----
    PEM
    CLOCK_SLACK = 2 * 86_400 # the PC clock may be put back by this much before the key is refused

    module_function

    def verify(payload, sig)
      require 'openssl'
      OpenSSL::PKey.read(PUBLIC_KEY).verify(nil, Base64.urlsafe_decode64(sig), payload)
    rescue StandardError, LoadError
      false
    end

    # 'EGC1.<payload>.<signature>' -> { 'n' => name, 'e' => end date, 'p' => plan, 'm' => machine code or nil } or nil
    def parse(key)
      pre, payload, sig = key.to_s.gsub(/\s+/, '').split('.')
      return nil unless pre == PREFIX && payload && sig && verify(payload, sig)

      JSON.parse(Base64.urlsafe_decode64(payload))
    rescue StandardError
      nil
    end

    # short code of THIS computer, shown in the licence card: a key can be tied to it
    def machine_code
      @machine_code ||= begin
        raw = begin
          require 'win32/registry'
          Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\\Microsoft\\Cryptography', Win32::Registry::KEY_READ | 0x0100) { |r| r['MachineGuid'].to_s }
        rescue StandardError, LoadError
          ''
        end
        raw = [ENV['COMPUTERNAME'], ENV['PROCESSOR_IDENTIFIER'], ENV['USERDOMAIN']].join('|') if raw.empty?
        h = Digest::SHA256.hexdigest("EGC|#{raw}")[0, 10].upcase
        "#{h[0, 5]}-#{h[5, 5]}"
      end
    end

    def data
      Config.read_json('license_b64', {})
    end

    # a key held in memory for this session only (the test runs use it); it is verified like any other key
    def session_key=(key)
      @session_key = key
    end

    # => { 'state' => 'licensed' | 'none' | 'expired' | 'wrong_machine' | 'clock', 'days' => n or nil, 'name', 'plan', 'expires', 'machine' }
    def status
      d = data
      out = { 'machine' => machine_code }
      info = parse(@session_key || d['key'])
      return out.merge('state' => 'none') unless info

      out = out.merge('name' => info['n'], 'plan' => info['p'], 'expires' => info['e'].to_s)
      return out.merge('state' => 'wrong_machine') if info['m'] && !info['m'].to_s.empty? && info['m'].to_s.upcase != machine_code
      return out.merge('state' => 'needs_machine') if BUILD_NEEDS_MACHINE && info['m'].to_s.empty?

      now = Time.now.to_i
      seen = d['seen'].to_i
      return out.merge('state' => 'clock') if now < seen - CLOCK_SLACK
      return out.merge('state' => 'expired', 'days' => 0, 'expires' => BUILD_EXPIRES.to_s) if build_expired?

      if now > seen + 3600
        d['seen'] = now
        Config.write_json('license_b64', d)
      end
      return out.merge('state' => 'licensed', 'days' => nil) if info['e'].to_s == 'perpetual'

      y, m, dd = info['e'].to_s.split('-').map(&:to_i)
      left = ((Time.local(y, m, dd) + 86_400 - Time.now) / 86_400.0).ceil # valid to the end of that day
      out.merge('state' => (left.positive? ? 'licensed' : 'expired'), 'days' => left)
    rescue StandardError
      { 'state' => 'none', 'machine' => (machine_code rescue '') }
    end

    # the trace line of a package made for one person ('' for a normal package)
    def build_mark
      BUILD_FOR.to_s.empty? ? '' : "Copy issued to: #{BUILD_FOR}#{BUILD_EXPIRES ? " - valid to #{BUILD_EXPIRES}" : ''}"
    end

    def build_expired?(now = Time.now)
      return false if BUILD_EXPIRES.to_s.empty?

      y, m, dd = BUILD_EXPIRES.to_s.split('-').map(&:to_i)
      now >= Time.local(y, m, dd) + 86_400
    rescue StandardError
      true
    end

    # stores a key whose signature is right; -> true / false (the state it gives is read with #status)
    def activate(key)
      return false unless parse(key)

      d = data
      d['key'] = key.to_s.gsub(/\s+/, '')
      Config.write_json('license_b64', d)
      true
    end

    def allowed?
      !ENFORCE || status['state'] == 'licensed'
    end

    REASON = {
      'none' => 'E.G.C Builder is not activated: press the red bar at the bottom of the E.G.C window and enter your activation key. | النسخة غير مفعّلة: اضغط الشريط الأحمر تحت في نافذة E.G.C واكتب مفتاح التفعيل.',
      'expired' => 'The activation key has expired: press the red bar at the bottom of the E.G.C window and enter a new key. | مدة مفتاح التفعيل انتهت: اضغط الشريط الأحمر تحت في نافذة E.G.C واكتب مفتاح جديد.',
      'wrong_machine' => 'This activation key was issued for another computer. | مفتاح التفعيل ده معمول لجهاز تاني.',
      'needs_machine' => 'This copy needs a key made for this computer: send the computer code shown in the activation window to the vendor. | النسخة دي محتاجة مفتاح معمول للجهاز ده: ابعت كود الجهاز اللي في نافذة التفعيل لصاحب البرنامج.',
      'clock' => 'The date of this computer was put back: set the right date, then try again. | تاريخ الجهاز اترجّع لورا: اظبط التاريخ الصحيح وجرّب تاني.'
    }.freeze

    def guard!
      return if allowed?

      raise REASON[status['state']] || REASON['none']
    end
  end
  # Entry points that build, change or list: checked here, in front of the method (so the method's own error handling never runs for
  # a refusal). Everything the window, the tools and the right-click menu do goes through one of these or through App.guard.
  { Kitchen => %i[generate place_unit rebuild_cabinet], Wardrobe => %i[generate], Cutlist => %i[analyse] }.each do |mod, names|
    mod.singleton_class.prepend(Module.new do
      names.each do |nm|
        define_method(nm) do |*a, **k, &b|
          License.guard!
          super(*a, **k, &b)
        end
      end
    end)
  end
end
