module Travis
  module Build
    class Script
      class Python < Script
        DEFAULTS = {
          python: '2.7',
          virtualenv: { system_site_packages: false }
        }

        REQUIREMENTS_MISSING = 'Could not locate requirements.txt. Override the install: key in your .travis.yml to install dependencies.'
        SCRIPT_MISSING       = 'Please override the script: key in your .travis.yml to run tests.'

        PYENV_PATH_FILE      = '/etc/profile.d/pyenv.sh'
        TEMP_PYENV_PATH_FILE = '/tmp/pyenv.sh'

        PYPY_VERSION_REGEX   = /\Apypy(?<python_compat_version>\d+)?(-(?<pypy_version>\d+(?:\.\d)*))?\z/

        def export
          super
          sh.export 'TRAVIS_PYTHON_VERSION', version, echo: false
        end

        def configure
          super
          sh.if "! -f #{virtualenv_activate}" do
            sh.echo "#{version} is not installed; attempting download", ansi: :yellow
            if pypy?
              install_pypy version
            else
              install_python_archive version
              setup_path version
            end
          end
        end

        def setup
          super
          sh.cmd "source #{virtualenv_activate}"
        end

        def announce
          sh.cmd 'python --version'
          sh.cmd 'pip --version'
          sh.export 'PIP_DISABLE_PIP_VERSION_CHECK', '1', echo: false
        end

        def setup_cache
          if data.cache?(:pip)
            sh.fold 'cache.pip' do
              sh.echo ''
              directory_cache.add '$HOME/.cache/pip'
            end
          end
        end

        def install
          sh.if '-f Requirements.txt' do
            sh.cmd 'pip install -r Requirements.txt', fold: 'install', retry: true
          end
          sh.elif '-f requirements.txt' do
            sh.cmd 'pip install -r requirements.txt', fold: 'install', retry: true
          end
          sh.else do
            sh.echo REQUIREMENTS_MISSING # , ansi: :red
          end
        end

        def script
          # This always fails the build, asking the user to provide a custom :script.
          # The Python ecosystem has no good default build command most of the
          # community aggrees on. Per discussion with jezjez, josh-k and others. MK
          sh.failure SCRIPT_MISSING
        end

        def cache_slug
          super << '--python-' << version
        end

        def use_directory_cache?
          super || data.cache?(:pip)
        end

        private

          def version
            config[:python].to_s
          end

          def virtualenv_activate
            "~/virtualenv/#{virtualenv}#{system_site_packages}/bin/activate"
          end

          def virtualenv
            pypy? ? version : "python#{version}"
          end

          def pypy?
            config[:python] =~ /pypy/i
          end

          def system_site_packages
            '_with_system_site_packages' if config[:virtualenv][:system_site_packages]
          end

          def install_python_archive(version = 'nightly')
            sh.raw archive_url_for('travis-python-archives', version)
            sh.cmd "curl -s -o python-#{version}.tar.bz2 ${archive_url}", echo: false, assert: true
            sh.cmd "sudo tar xjf python-#{version}.tar.bz2 --directory /", echo: false, assert: true
            sh.cmd "rm python-#{version}.tar.bz2", echo: false
          end

          def install_pypy(version)
            if pypy_archive_url
              archive = "pypy.tar.bz2"
              install_dir = "/usr/local/pypy"
              sh.cmd "curl -s -L -o #{archive} #{pypy_archive_url}"
              sh.cmd "mkdir #{install_dir}", sudo: true, echo: false
              sh.cmd "tar xjf #{archive} -C #{install_dir} --strip-components=1", sudo: true
              sh.export "PATH", "#{install_dir}/bin:$PATH", echo: true
              sh.cmd "rm #{archive}", echo: false
              sh.cmd "rm -f $HOME/virtualenv/pypy{,3}"
              sh.cmd "virtualenv --distribute --python=/usr/local/pypy/bin/python $HOME/virtualenv/#{virtualenv}"
            end
          end

          def pypy_archive_url(vers=config[:python], arch='linux64')
            pypy? && md = PYPY_VERSION_REGEX.match(vers)
            if md[:python_compat_version] && md[:pypy_version]
              "https://bitbucket.org/pypy/pypy/downloads/pypy%s-v%s-%s.tar.bz2" % [md[:python_compat_version], md[:pypy_version], arch]
            end
          end

          def setup_path(version = 'nightly')
            sh.cmd "sed -e 's|export PATH=\\(.*\\)$|export PATH=/opt/python/#{version}/bin:\\1|' #{PYENV_PATH_FILE} > #{TEMP_PYENV_PATH_FILE}"
            sh.cmd "cat #{TEMP_PYENV_PATH_FILE} | sudo tee #{PYENV_PATH_FILE} > /dev/null"
          end
      end
    end
  end
end

