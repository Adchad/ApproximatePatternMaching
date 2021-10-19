/**
 * APPROXIMATE PATTERN MATCHING
 *
 * INF560 X2016
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include <math.h>

#include <cuda.h>                                                               
#include <cuda_runtime.h>                                                       
#include <helper_cuda.h>   

#define APM_DEBUG 0

char *read_input_file(char *filename, int *size) {
  char *buf;
  off_t fsize;
  int fd = 0;
  int n_bytes = 1;

  /* Open the text file */
  fd = open(filename, O_RDONLY);
  if (fd == -1) {
    fprintf(stderr, "Unable to open the text file <%s>\n", filename);
    return NULL;
  }

  /* Get the number of characters in the textfile */
  fsize = lseek(fd, 0, SEEK_END);
  lseek(fd, 0, SEEK_SET);

  /* TODO check return of lseek */

#if APM_DEBUG
  printf("File length: %lld\n", fsize);
#endif

  /* Allocate data to copy the target text */
  buf = (char *)malloc(fsize * sizeof(char));
  if (buf == NULL) {
    fprintf(stderr, "Unable to allocate %lld byte(s) for main array\n", fsize);
    return NULL;
  }

  n_bytes = read(fd, buf, fsize);
  if (n_bytes != fsize) {
    fprintf(stderr,
            "Unable to copy %lld byte(s) from text file (%d byte(s) copied)\n",
            fsize, n_bytes);
    return NULL;
  }

#if APM_DEBUG
  printf("Number of read bytes: %d\n", n_bytes);
#endif

  *size = n_bytes;

  close(fd);

  return buf;
}

#define MIN3(a, b, c)                                                          \
  ((a) < (b) ? ((a) < (c) ? (a) : (c)) : ((b) < (c) ? (b) : (c)))

__device__ int levenshtein(char *s1, char *s2, int len, int *column) {

printf("Helloooo\n");
  unsigned int x, y, lastdiag, olddiag;

  for (y = 1; y <= len; y++) {
    column[y] = y;
  }
  for (x = 1; x <= len; x++) {
    column[0] = x;
    lastdiag = x - 1;
    for (y = 1; y <= len; y++) {
      olddiag = column[y];
      column[y] = MIN3(column[y] + 1, column[y - 1] + 1, lastdiag + (s1[y - 1] == s2[x - 1] ? 0 : 1));
      lastdiag = olddiag;
    }
  }
  return (column[len]);
}


__global__ void processing(int size_pattern, char * pattern, int* column, int n_bytes, int approx_factor, char *buf, int *n_matches_j ){
    int j = blockIdx.x*blockDim.x + threadIdx.x;

    int distance = 0;
    int size;
    size = size_pattern;
    if (n_bytes - j < size_pattern) {
      size = n_bytes - j;
    }

    distance = levenshtein(pattern, &buf[j], size, column);

    if (distance <= approx_factor) {
      n_matches_j[j] = 1;

    }
    else{n_matches_j[j] = 0;}

    printf("Noyau : j : %d, n_match : %d\n", j, n_matches_j[j]);



}

int main(int argc, char **argv) {
  char **pattern;
  char *filename;
  int approx_factor = 0;
  int nb_patterns = 0;
  int i;
  char *buf;
  struct timeval t1, t2;
  double duration;
  int n_bytes;
  int *n_matches;

  /* Check number of arguments */
  if (argc < 4) {
    printf("Usage: %s approximation_factor "
           "dna_database pattern1 pattern2 ...\n",
           argv[0]);
    return 1;
  }

  /* Get the distance factor */
  approx_factor = atoi(argv[1]);

  /* Grab the filename containing the target text */
  filename = argv[2];

  /* Get the number of patterns that the user wants to search for */
  nb_patterns = argc - 3;

  /* Fill the pattern array */
  pattern = (char **)malloc(nb_patterns * sizeof(char *));
  if (pattern == NULL) {
    fprintf(stderr, "Unable to allocate array of pattern of size %d\n",
            nb_patterns);
    return 1;
  }

  /* Grab the patterns */
  for (i = 0; i < nb_patterns; i++) {
    int l;

    l = strlen(argv[i + 3]);
    if (l <= 0) {
      fprintf(stderr, "Error while parsing argument %d\n", i + 3);
      return 1;
    }

    pattern[i] = (char *)malloc((l + 1) * sizeof(char));
    if (pattern[i] == NULL) {
      fprintf(stderr, "Unable to allocate string of size %d\n", l);
      return 1;
    }

    strncpy(pattern[i], argv[i + 3], (l + 1));
  }

  printf("Approximate Pattern Mathing: "
         "looking for %d pattern(s) in file %s w/ distance of %d\n",
         nb_patterns, filename, approx_factor);

  buf = read_input_file(filename, &n_bytes);
  if (buf == NULL) {
    return 1;
  }

  /* Allocate the array of matches */
  n_matches = (int *)malloc(nb_patterns * sizeof(int));
  if (n_matches == NULL) {
    fprintf(stderr, "Error: unable to allocate memory for %ldB\n",
            nb_patterns * sizeof(int));
    return 1;
  }

  /*****
   * BEGIN MAIN LOOP
   ******/

  /* Timer start */
  gettimeofday(&t1, NULL);

  for (i = 0; i < nb_patterns; i++) {

    int size_pattern = strlen(pattern[i]);
    
    int * n_matches_j = (int*) malloc((n_bytes) * sizeof(int));

     for(int j=0; j<n_bytes; j++){
      n_matches[i]=0;
    }
    

    int *gpu_column, *gpu_n_matches_j;

    n_matches[i] = 0;

    char * gpu_pattern, * gpu_buf;

    cudaMalloc((void **) &gpu_pattern, (size_pattern) * sizeof(char));
    cudaMalloc((void **) &gpu_buf, (n_bytes) * sizeof(char));
    cudaMalloc((void **) &gpu_column, (size_pattern + 1) * sizeof(int));
    cudaMalloc((void **) &gpu_n_matches_j, (n_bytes) * sizeof(int));

    cudaMemcpy(gpu_pattern, pattern[i],(size_pattern) * sizeof(char), cudaMemcpyHostToDevice );
    cudaMemcpy(gpu_buf, buf,(n_bytes) * sizeof(char), cudaMemcpyHostToDevice );
    //cudaMemcpy(gpu_column, (size_pattern + 1) * sizeof(int), cudaMemcpyHostToDevice );
    cudaMemcpy(gpu_n_matches_j,n_matches_j, (n_bytes) * sizeof(int), cudaMemcpyHostToDevice );


    int blocksize = 1024;

    int real_blocksize = MIN3(blocksize, blocksize, n_bytes);

    dim3 dimBlock (blocksize);
    dim3 dimGrid(ceil((n_bytes/(float)blocksize)));

    int test = ceil((n_bytes/(float)blocksize));

    printf("test : %d\n", test);
  
    processing<<<dimGrid, dimBlock>>>(size_pattern, gpu_pattern, gpu_column, n_bytes, approx_factor, gpu_buf, gpu_n_matches_j);

    

    cudaMemcpy(n_matches_j, gpu_n_matches_j ,(n_bytes) * sizeof(int), cudaMemcpyDeviceToHost) ;

    for(int j=0; j<n_bytes; j++){
      printf("Pas Noyau : j : %d, n_match : %d\n", j, n_matches_j[j]);
      n_matches[i]+=n_matches_j[j];
    }
    

    cudaFree(gpu_column);
    cudaFree(gpu_pattern);
    cudaFree(gpu_buf);
    cudaFree(gpu_n_matches_j);
  }

  /* Timer stop */
  gettimeofday(&t2, NULL);

  duration = (t2.tv_sec - t1.tv_sec) + ((t2.tv_usec - t1.tv_usec) / 1e6);

  printf("APM done in %lf s\n", duration);

  /*****
   * END MAIN LOOP
   ******/
    
  for (i = 0; i < nb_patterns; i++) {
    printf("Number of matches for pattern <%s>: %d\n", pattern[i],
           n_matches[i]);
  }

  return 0;
}
