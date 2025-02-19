//
// Common stuff
// ʕ•ᴥ•ʔ


import * as localforage from "localforage"


export const APP_INFO = {
  creator: "icidasset",
  name: "Diffuse"
}


export const ODD_CONFIG = {
  namespace: APP_INFO,
  permissions: {
    app: APP_INFO,
    fs: { public: [ { directory: [ "Apps", APP_INFO.creator, APP_INFO.name ] } ] }
  },
  debug: true,
}



// FUNCTIONS


export function db(storeName: string = "main"): LocalForage {
  return localforage.createInstance({
    name: "diffuse",
    storeName
  })
}


export function fileExtension(mimeType) {
  const audioId = mimeType.toLowerCase().split("/")[ 1 ]

  switch (audioId) {
    case "mp3": return "mp3";
    case "mpeg": return "mp3";

    case "mp4a-latm": return "m4a";
    case "mp4": return "m4a";
    case "x-m4a": return "m4a";

    case "flac": return "flac";
    case "x-flac": return "flac";
    case "ogg": return "ogg";

    case "wav": return "wav";
    case "wave": return "wav";

    case "webm": return "webm";

    case "opus": return "opus";
  }
}


export function mimeType(fileExt) {
  switch (fileExt) {
    case "mp3": return "audio/mpeg";
    case "mp4": return "audio/mp4";
    case "m4a": return "audio/mp4";
    case "flac": return "audio/flac";
    case "ogg": return "audio/ogg";
    case "wav": return "audio/wave";
    case "webm": return "audio/webm";
    case "opus": return "audio/opus";
  }
}
