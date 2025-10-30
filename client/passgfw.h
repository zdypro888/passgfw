#ifndef PASSGFW_H
#define PASSGFW_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * PassGFW C API
 * 
 * Provides C interface for cross-language compatibility
 * Suitable for iOS/Android/HarmonyOS integration
 */

// Opaque handle
typedef void* PassGFWDetector;

/**
 * Create detector instance
 * @return Detector handle, NULL on failure
 */
PassGFWDetector passgfw_create();

/**
 * Destroy detector instance
 * @param detector Detector handle
 */
void passgfw_destroy(PassGFWDetector detector);

/**
 * Get available server domain (blocking call)
 * 
 * This function will block until finding an available server
 * Loop infinitely with retries if all URLs fail
 * 
 * @param detector Detector handle
 * @param custom_data Custom data to send with request (can be NULL)
 * @param out_domain Output buffer for domain string
 * @param domain_size Buffer size
 * @return 0 on success, -1 on failure
 */
int passgfw_get_final_server(PassGFWDetector detector,
                             const char* custom_data,
                             char* out_domain, 
                             int domain_size);

/**
 * Set custom URL list (override built-in list)
 * @param detector Detector handle
 * @param urls URL array
 * @param count Array length
 * @return 0 on success, -1 on failure
 */
int passgfw_set_url_list(PassGFWDetector detector, 
                        const char** urls, 
                        int count);

/**
 * Add URL to list
 * @param detector Detector handle
 * @param url URL to add
 * @return 0 on success, -1 on failure
 */
int passgfw_add_url(PassGFWDetector detector, const char* url);

/**
 * Get last error message
 * @param detector Detector handle
 * @param out_error Output buffer for error string
 * @param error_size Buffer size
 * @return 0 on success, -1 on failure
 */
int passgfw_get_last_error(PassGFWDetector detector, 
                           char* out_error, 
                           int error_size);

#ifdef __cplusplus
}
#endif

#endif // PASSGFW_H
