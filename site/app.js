(function () {
  var downloadButton = document.getElementById('download-button');
  var latestVersion = document.getElementById('latest-version');
  var releaseList = document.getElementById('release-list');
  var releaseListNote = document.querySelector('.release-list-note');

  var fallbackDownloadURL =
    'https://github.com/T3pp31/Transnote/releases/latest/download/Transnote.dmg';
  var expectedRepository = 'T3pp31/Transnote';
  var allowedDownloadHosts = ['github.com', 'objects.githubusercontent.com'];
  var latestTagName = null;

  function isAllowedDownloadURL(urlString) {
    try {
      var url = new URL(urlString);
      if (url.protocol !== 'https:') {
        return false;
      }
      var host = url.hostname.toLowerCase();
      return allowedDownloadHosts.some(function (allowedHost) {
        return host === allowedHost;
      });
    } catch (error) {
      return false;
    }
  }

  function formatDate(isoString) {
    if (!isoString) {
      return '';
    }
    var date = new Date(isoString);
    if (isNaN(date.getTime())) {
      return '';
    }
    return (
      date.getFullYear() + '年' + (date.getMonth() + 1) + '月' + date.getDate() + '日'
    );
  }

  function findDmgAsset(assets) {
    return (assets || []).find(function (asset) {
      return /^Transnote-[\d.]+\.dmg$/.test(asset.name);
    });
  }

  function findSha256Asset(assets, dmgAsset) {
    if (!dmgAsset) {
      return null;
    }
    var expectedName = dmgAsset.name + '.sha256';
    return (assets || []).find(function (asset) {
      return asset.name === expectedName;
    });
  }

  function renderReleaseList(releases) {
    if (!releaseList) {
      return;
    }
    // Clear existing items when re-rendering (since this is called again after latest resolves)
    while (releaseList.firstChild) {
      releaseList.removeChild(releaseList.firstChild);
    }

    var rendered = 0;
    releases.forEach(function (release) {
      if (typeof release.tag_name !== 'string') {
        return;
      }
      var dmg = findDmgAsset(release.assets);
      if (!dmg || !isAllowedDownloadURL(dmg.browser_download_url)) {
        return;
      }
      var sha = findSha256Asset(release.assets, dmg);
      var li = document.createElement('li');
      li.className = 'release-item';

      var versionRow = document.createElement('div');
      versionRow.className = 'release-version-row';

      var version = document.createElement('span');
      version.className = 'release-version';
      version.textContent = release.tag_name;
      versionRow.appendChild(version);

      // Show the "latest" badge only when it matches releases/latest
      if (release.tag_name === latestTagName) {
        var latestBadge = document.createElement('span');
        latestBadge.className = 'badge';
        latestBadge.textContent = '最新';
        versionRow.appendChild(latestBadge);
      }

      if (release.prerelease) {
        var preBadge = document.createElement('span');
        preBadge.className = 'badge';
        preBadge.textContent = 'β';
        versionRow.appendChild(preBadge);
      }

      var date = document.createElement('span');
      date.className = 'release-date';
      date.textContent = formatDate(release.published_at) || '';
      date.setAttribute(
        'aria-label',
        release.published_at ? '公開日 ' + release.published_at : '公開日不明'
      );
      versionRow.appendChild(date);

      li.appendChild(versionRow);

      var links = document.createElement('div');
      links.className = 'release-links';

      var dmgLink = document.createElement('a');
      dmgLink.href = dmg.browser_download_url;
      dmgLink.textContent = dmg.name;
      dmgLink.className = 'release-download';
      dmgLink.setAttribute('rel', 'noopener');
      links.appendChild(dmgLink);

      if (sha && isAllowedDownloadURL(sha.browser_download_url)) {
        var shaLink = document.createElement('a');
        shaLink.href = sha.browser_download_url;
        shaLink.textContent = 'SHA256';
        shaLink.className = 'release-sha';
        shaLink.setAttribute('rel', 'noopener');
        links.appendChild(shaLink);
      }

      var notesLink = document.createElement('a');
      notesLink.href = release.html_url;
      notesLink.textContent = 'リリースノート';
      notesLink.className = 'release-notes';
      notesLink.setAttribute('rel', 'noopener');
      links.appendChild(notesLink);

      li.appendChild(links);
      releaseList.appendChild(li);
      rendered += 1;
    });

    if (rendered === 0) {
      showReleaseListError();
    } else if (releaseListNote) {
      releaseListNote.textContent = 'すべてのリリースの DMG をダウンロードできます。';
    }
  }

  function showReleaseListError() {
    if (!releaseListNote) {
      return;
    }
    releaseListNote.textContent = '';
    var text = document.createTextNode('リリース一覧を取得できませんでした。');
    var link = document.createElement('a');
    link.href = 'https://github.com/T3pp31/Transnote/releases';
    link.textContent = 'GitHub Releases';
    releaseListNote.appendChild(text);
    releaseListNote.appendChild(document.createTextNode(' '));
    releaseListNote.appendChild(link);
    releaseListNote.appendChild(document.createTextNode(' をご覧ください。'));
  }

  // The list fetch may complete before latest, so once latest
  // resolves later, re-render to add the "latest" badge.
  var fetchedReleases = null;
  function rerenderIfNeeded() {
    if (fetchedReleases) {
      renderReleaseList(fetchedReleases);
    }
  }

  fetch('https://api.github.com/repos/T3pp31/Transnote/releases/latest')
    .then(function (response) {
      return response.json();
    })
    .then(function (release) {
      var expectedReleasePagePrefix =
        'https://github.com/' + expectedRepository + '/releases/';
      if (
        !release ||
        typeof release.html_url !== 'string' ||
        !release.html_url.startsWith(expectedReleasePagePrefix)
      ) {
        return;
      }

      var assets = release.assets || [];
      var dmg = assets.find(function (asset) {
        return asset.name === 'Transnote.dmg';
      });

      if (downloadButton) {
        if (dmg && isAllowedDownloadURL(dmg.browser_download_url)) {
          downloadButton.href = dmg.browser_download_url;
        } else {
          downloadButton.href = fallbackDownloadURL;
        }
      }

      if (typeof release.tag_name === 'string') {
        latestTagName = release.tag_name;
        if (latestVersion) {
          latestVersion.textContent = '最新版 ' + release.tag_name;
        }
      }
      rerenderIfNeeded();
    })
    .catch(function () {
      rerenderIfNeeded();
    });

  fetch('https://api.github.com/repos/T3pp31/Transnote/releases?per_page=30')
    .then(function (response) {
      return response.json();
    })
    .then(function (releases) {
      if (!Array.isArray(releases)) {
        showReleaseListError();
        return;
      }
      fetchedReleases = releases;
      renderReleaseList(releases);
    })
    .catch(function () {
      showReleaseListError();
    });

  // For automated tests from Node.js (ignored in the browser, where module does not exist)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      isAllowedDownloadURL: isAllowedDownloadURL,
      formatDate: formatDate,
      findDmgAsset: findDmgAsset,
      findSha256Asset: findSha256Asset
    };
  }
})();
