import http from '@ohos.net.http';

/**
 * HTTP Response
 */
export interface HTTPResponse {
  success: boolean;
  statusCode: number;
  body: string;
  error: string | null;
}

/**
 * Network Client for HTTP requests
 */
export class NetworkClient {
  private timeout: number;

  constructor(timeout: number = 10000) {
    this.timeout = timeout;
  }

  /**
   * POST request with raw binary data
   */
  async postBytes(url: string, body: Uint8Array): Promise<HTTPResponse> {
    const httpRequest = http.createHttp();

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/octet-stream',
          'User-Agent': 'PassGFW/2.2 ArkTS'
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.timeout,
        readTimeout: this.timeout
      });

      const success = response.responseCode >= 200 && response.responseCode < 300;

      return {
        success: success,
        statusCode: response.responseCode,
        body: response.result as string,
        error: success ? null : `HTTP ${response.responseCode}`
      };
    } catch (error) {
      return {
        success: false,
        statusCode: 0,
        body: '',
        error: error?.message || 'Network error'
      };
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * POST request with JSON string
   */
  async post(url: string, jsonBody: string): Promise<HTTPResponse> {
    const httpRequest = http.createHttp();

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'User-Agent': 'PassGFW/2.2 ArkTS'
        },
        extraData: jsonBody,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.timeout,
        readTimeout: this.timeout
      });

      const success = response.responseCode >= 200 && response.responseCode < 300;

      return {
        success: success,
        statusCode: response.responseCode,
        body: response.result as string,
        error: success ? null : `HTTP ${response.responseCode}`
      };
    } catch (error) {
      return {
        success: false,
        statusCode: 0,
        body: '',
        error: error?.message || 'Network error'
      };
    } finally {
      httpRequest.destroy();
    }
  }
  
  /**
   * GET request
   */
  async get(url: string): Promise<HTTPResponse> {
    const httpRequest = http.createHttp();
    
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'PassGFW/1.0 ArkTS'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.timeout,
        readTimeout: this.timeout
      });
      
      const success = response.responseCode >= 200 && response.responseCode < 300;
      
      return {
        success: success,
        statusCode: response.responseCode,
        body: response.result as string,
        error: success ? null : `HTTP ${response.responseCode}`
      };
    } catch (error) {
      return {
        success: false,
        statusCode: 0,
        body: '',
        error: error?.message || 'Network error'
      };
    } finally {
      httpRequest.destroy();
    }
  }
}

