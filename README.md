# Puppet Core Community Triage

A small Sinatra application to link Puppet open source pull requests to the community [Trello board](https://trello.com/b/YCzBvzHW). Community contributions from [Puppet](https://github.com/puppetlabs/puppet), [Facter](https://github.com/puppetlabs/facter), [Hiera](https://github.com/puppetlabs/hiera), and [Strings](https://github.com/puppetlabs/puppetlabs-strings) are tracked on this board.

Generally, actions should be taken on the pull requests themselves on GitHub which will then prompt Trello to automatically adjust the corresponding cards appropriately. There are a few manual steps, which are detailed below.

#### Trello Lists and Workflows
**Open Pull Requests**
* This list represents brand new pull requests which have not yet been triaged by the core team. 
* Cards in this list are auto-generated upon a pull request being opened or reopened against one of the four open source projects mentioned above.

**Waiting on Us**
* Pull requests in this list have been triaged and are waiting for review from a core developer.
* Cards are automatically moved to this list when the associated pull request is commented on in GitHub by a non-core developer, new commits are pushed, or the "Triaged" label is added.
* Core team developer bandwidth is the largest bottleneck on merging communiy contributions, so many pull requests will (realistically) spend significant time here, varying with change complexity.

**Waiting on Contributor**
* Pull requests in this list have had some core developer review and are waiting for updates to address questions or issues.
* Cards are generally manually moved into this list upon associated pull request review, but are also automatically moved when the "Waiting for Contributor" label is added to the pull request on GitHub.

**Waiting on Deep Dive**
* Pull requests in this list require additional core developer investigation and possibly design discussion. Often, seeking expert knowledge of specific areas of the code base is also required.
* Cards are generally manually moved into this list upon associated pull request review, but are also automatically moved when the "Blocked" label is added to the pull request on GitHub.
