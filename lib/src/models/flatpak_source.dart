sealed class FlatpakSource {
  Map<String, dynamic> toJson();
}

final class ArchiveSource extends FlatpakSource {
  final String url;
  final String sha256;
  final String dest;
  final int stripComponents;
  final List<String>? onlyArches;

  ArchiveSource({
    required this.url,
    required this.sha256,
    required this.dest,
    this.stripComponents = 1,
    this.onlyArches,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'archive',
        'url': url,
        'sha256': sha256,
        'dest': dest,
        'strip-components': stripComponents,
        if (onlyArches != null) 'only-arches': onlyArches,
      };
}

final class GitSource extends FlatpakSource {
  final String url;
  final String? tag;
  final String? commit;
  final String? dest;
  final bool? disableSubmodules;

  GitSource({
    required this.url,
    this.tag,
    this.commit,
    this.dest,
    this.disableSubmodules,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'git',
        'url': url,
        if (tag != null) 'tag': tag,
        if (commit != null) 'commit': commit,
        if (dest != null) 'dest': dest,
        if (disableSubmodules != null) 'disable-submodules': disableSubmodules,
      };
}

final class FileSource extends FlatpakSource {
  final String url;
  final String sha256;
  final String? dest;
  final String? destFilename;

  FileSource({
    required this.url,
    required this.sha256,
    this.dest,
    this.destFilename,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'file',
        'url': url,
        'sha256': sha256,
        if (dest != null) 'dest': dest,
        if (destFilename != null) 'dest-filename': destFilename,
      };
}

final class ScriptSource extends FlatpakSource {
  final List<String> commands;
  final String? dest;
  final String? destFilename;

  ScriptSource({
    required this.commands,
    this.dest,
    this.destFilename,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'script',
        'commands': commands,
        if (dest != null) 'dest': dest,
        if (destFilename != null) 'dest-filename': destFilename,
      };
}

final class PatchSource extends FlatpakSource {
  final String path;
  final String? dest;

  PatchSource({required this.path, this.dest});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'patch',
        'path': path,
        if (dest != null) 'dest': dest,
      };
}
