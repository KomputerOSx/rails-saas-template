class MaintenanceMode
  def self.file_path
    if Rails.env.test?
      warn "DEBUG file_path worker=#{ENV["TEST_ENV_NUMBER"].inspect} pid=#{Process.pid} thread=#{Thread.current.object_id}"
      Rails.root.join("tmp", "maintenance_mode#{ENV["TEST_ENV_NUMBER"]}.json")
    else
      Rails.root.join("storage", "maintenance_mode.json")
    end
  end

  def self.status
    return { enabled: false, message: nil } unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))
    { enabled: data["enabled"] == true, message: data["message"] }
  rescue JSON::ParserError, Errno::ENOENT
    { enabled: false, message: nil }
  end

  def self.enabled?
    status[:enabled]
  end

  def self.enable!(message:)
    File.write(file_path, { enabled: true, message: message }.to_json)
  end

  def self.disable!
    File.delete(file_path) if File.exist?(file_path)
  end
end
