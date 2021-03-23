# <a name="title"></a> Kitchen::Linode
[![Gem](https://img.shields.io/gem/v/kitchen-linode.svg)](https://rubygems.org/gems/kitchen-linode)
[![Gem](https://img.shields.io/gem/dt/kitchen-linode.svg)](https://rubygems.org/gems/kitchen-linode)
[![Gem](https://img.shields.io/gem/dtv/kitchen-linode.svg)](https://rubygems.org/gems/kitchen-linode)
[![Code Climate](https://codeclimate.com/github/ssplatt/kitchen-linode/badges/gpa.svg)](https://codeclimate.com/github/ssplatt/kitchen-linode)
[![Test Coverage](https://codeclimate.com/github/ssplatt/kitchen-linode/badges/coverage.svg)](https://codeclimate.com/github/ssplatt/kitchen-linode/coverage)
[![Build Status](https://travis-ci.org/ssplatt/kitchen-linode.svg?branch=master)](https://travis-ci.org/ssplatt/kitchen-linode)

A Test Kitchen Driver for [Linode](http://www.linode.com).

[![asciicast](https://asciinema.org/a/44348.png)](https://asciinema.org/a/44348)

## <a name="requirements"></a> Requirements

Requires [Test Kitchen](https://kitchen.ci/) and a [Linode](http://www.linode.com) account.

```sh
gem install test-kitchen
```

## <a name="installation"></a> Installation and Setup

The gem file is hosted at [RubyGems](https://rubygems.org/gems/kitchen-linode). To install the gem file, run:

```sh
gem install kitchen-linode
```

Or, install with bundler if you have a Gemfile
Please read the [Driver usage][driver_usage] page for more details.

## <a name="config"></a> Configuration

For many of these, you can specify an ID number, a full name, or a partial name that will try to match something in the list but may not match exactly what you want.

```
LINODE_TOKEN        Linode API Token environment variable, default: nil
:username           ssh user name, default: "root"
:password           password for user, default: randomly generated hash
:image              Linux distribution, default: "linode/debian10"
:region             region, default: "us-east"
:type               linode instance type, default: "g6-standard-1"
:kernel             Linux kernel, default: "linode/grub2"
:private_key_path   Location of your private key file, default: "~/.ssh/id_rsa"
:public_key_path    Location of your public key file, default: "~/.ssh/id_rsa.pub"
:ssh_timeout        ssh timeout, default: 600 (seconds)
:sudo               use sudo, default: True
:port               ssh port, default: 22
:server_name        set the hostname and linode name
```

## <a name="usage"></a> Usage

First, set your Linode API key in an environment variable:

```sh
export LINODE_API_KEY='myrandomkey123123213h123bh12'
```

Then, create a .kitchen.yml file:

```yaml
---
driver:
  name: linode

provisioner:
  name: salt_solo
  formula: vim
  state_top:
    base:
      "*":
        - vim

platforms:
  - name: debian_jessie

suites:
  - name: default
```

then you're ready to run `kitchen test` or `kitchen converge`

```sh
kitchen test
```

If you want to create a second yaml config; one for using Vagrant locally but another to use the Linode driver when run on your CI server, create a config with a name like `.kitchen-ci.yml`:

```yaml
---
driver:
  name: linode

provisioner:
  name: salt_solo
  formula: vim
  state_top:
    base:
      "*":
        - vim

platforms:
  - name: debian_jessie

suites:
  - name: default
```

Then you can run the second config by changing the KITCHEN_YAML environment variable:

```sh
KITCHEN_YAML="./.kitchen-ci.yml" kitchen test
```

If you want to change any of the default settings, you can do so in the 'platforms' area:

```yaml
# ...<snip>...
platforms:
  - name: debian_jessie
    driver:
      flavor: 2048
      data_center: Dallas
      kernel: 4.0.2-x86_64-linode56
      image: Debian 7
# ...<snip>...
```

## <a name="development"></a> Development

* Source hosted at [GitHub][repo]
* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## <a name="authors"></a> Authors

Created and maintained by [Brett Taylor][author] (<btaylor@linode.com>)

## <a name="license"></a> License

Apache 2.0 (see [LICENSE][license])


[author]:           <https://github.com/ssplatt>
[issues]:           <https://github.com/ssplatt/kitchen-linode/issues>
[license]:          <https://github.com/ssplatt/kitchen-linode/blob/master/LICENSE>
[repo]:             <https://github.com/ssplatt/kitchen-linode>
[driver_usage]:     <https://kitchen.ci/docs/reference/configuration/>
