let callbackCounter = 0;

function uniqueCallbackName(prefix) {
  return `${prefix}_callback_${Date.now()}_${callbackCounter++}`;
}

export function exec(command, options = {}) {
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== "function") {
      reject(new Error("KernelSU WebUI API is unavailable."));
      return;
    }

    const callbackName = uniqueCallbackName("exec");
    window[callbackName] = (errno, stdout, stderr) => {
      delete window[callbackName];
      resolve({ errno, stdout, stderr });
    };

    try {
      window.ksu.exec(command, JSON.stringify(options), callbackName);
    } catch (error) {
      delete window[callbackName];
      reject(error);
    }
  });
}

export function toast(message) {
  if (window.ksu && typeof window.ksu.toast === "function") {
    window.ksu.toast(message);
  }
}

