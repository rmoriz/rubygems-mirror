require 'rubygems'
require 'fileutils'

class Gem::Mirror
  autoload :Fetcher, 'rubygems/mirror/fetcher'
  autoload :Pool, 'rubygems/mirror/pool'

  SPECS_FILE              = "specs.#{Gem.marshal_version}"
  LATEST_SPECS_FILE       = "latest_specs.#{Gem.marshal_version}"
  PRERELEASE_SPECS_FILE   = "prerelease_specs.#{Gem.marshal_version}"

  DEFAULT_URI = 'http://production.s3.rubygems.org/'
  DEFAULT_TO = File.join(Gem.user_home, '.gem', 'mirror')

  RUBY = 'ruby'

  def initialize(from = DEFAULT_URI, to = DEFAULT_TO, parallelism = 10)
    @from, @to = from, to
    @to_tmp = '/tmp'
    @fetcher = Fetcher.new
    @pool = Pool.new(parallelism)
  end

  def from(*args)
    File.join(@from, *args)
  end

  def to(*args)
    File.join(@to, *args)
  end

  def to_tmp(*args)
    File.join(@to_tmp, *args)
  end
  def update_specs(filename = SPECS_FILE)
    filez = filename + '.gz'
    specz = to_tmp(filez)
    @fetcher.fetch(from(filez), specz)
    open(to_tmp(filename), 'wb') { |f| f << Gem.gunzip(File.read(specz)) }
  end

  def update_latest_specs(filename = LATEST_SPECS_FILE)
    update_specs(filename)
  end

  def update_prerelease_specs(filename = PRERELEASE_SPECS_FILE)
    update_specs(filename)
  end

  def gems
    gems = Marshal.load(File.read(to_tmp(SPECS_FILE)))
    gems += Marshal.load(File.read(to_tmp(PRERELEASE_SPECS_FILE)))
    gems += Marshal.load(File.read(to_tmp(LATEST_SPECS_FILE)))
    gems.map! do |name, ver, plat|
      # If the platform is ruby, it is not in the gem name
      "#{name}-#{ver}#{"-#{plat}" unless plat == RUBY}.gem"
    end
    gems
  end

  def existing_gems
    Dir[to('gems', '*.gem')].entries.map { |f| File.basename(f) }
  end

  def gems_to_fetch
    gems - existing_gems
  end

  def gems_to_delete
    existing_gems - gems
  end

  def update_gems
    gems_to_fetch.each do |g|
      @pool.job do
        print "."; STDOUT.flush
        @fetcher.fetch(from('gems', g), to('gems', g))
        yield
      end
    end
    print "\n"; STDOUT.flush

    @pool.run_til_done
  end

  def delete_gems
    gems_to_delete.each do |g|
      @pool.job do
        File.delete(to('gems', g))
        yield
      end
    end

    @pool.run_til_done
  end

  def update_all_specs
    update_specs
    update_latest_specs
    update_prerelease_specs
  end

  def update
    update_specs
    update_latest_specs
    update_prerelease_specs
    update_gems
  end
end