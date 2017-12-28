import { NativeEventEmitter, NativeModules } from 'react-native';
const { RNScreenshotDetector } = NativeModules;

export const SCREENSHOT_EVENT = 'ScreenshotTaken';

export function subscribe(cb) {
  const eventEmitter = new NativeEventEmitter(RNScreenshotDetector);
  eventEmitter.addListener(SCREENSHOT_EVENT, cb, {});
  return eventEmitter;
}

export function unsubscribe(eventEmitter) {
  eventEmitter.removeAllListeners(SCREENSHOT_EVENT);
}

export function saveImage(obj, successCallBack, errorCallback)
{
  var defaults = {
      imageType: 'jpg',
      width: 2048,
      height: 2048,
  }
  var parameters = {...defaults, ...obj};
  console.log("parameters", parameters);
  RNScreenshotDetector.saveImage(parameters, successCallBack, errorCallback);
}
