# APT dists merge

## Description

APT dists merge provides a tool and a library to merge `dists/` contents for APT repository.

Generally, you should use more general APT repository management tool such as [aptly](https://www.aptly.info/) and [reprepro](https://salsa.debian.org/brlink/reprepro).

APT dists merge is useful when you want to manage `pool/` by yourself and add `.deb`s incrementally without keeping all `.deb`s for the target APT repository on local.

Use cases:

  * [Apache Arrow](https://github.com/apache/arrow/blob/master/dev/release/binary-task.rb)
  * [Groonga](https://github.com/groonga/packages.groonga.org)
  * [Red Data Tools](https://github.com/red-data-tools/packages.red-data-tools.org)

## Install

```bash
gem install apt-dists-merge
```

## Usage

Tool:

```bash
apt-dists-merge --base base/dists/ --new new/dists/ --output merged/dists/
```

Library:

```ruby
require "apt-dists-merge"

merger = APTDistsMerge::Merger.new("base/dists/", "new/dists/")
merger.merge("merged/dists/")
```

## License

The MIT license. See `LICENSE.txt` for details.
