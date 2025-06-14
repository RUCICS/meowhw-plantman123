#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
long offset;
long page_size;  // 默认为4KB

void init_pagesize() {
    page_size = sysconf(_SC_PAGESIZE);
}

/*获得刚好大于等于block的2的整次幂*/
long power_of_2(long block_size) {
    long res = 1;
    while (1) {
        res *= 2;
        if (res >= block_size) return res;
    }
}


/*获取缓存区大小*/
long io_blocksize(int fd) {
    int muti = 1;
    struct stat st;
    if(fstat(fd, &st) == -1) {perror("fstat");return page_size;}
    long file_size = st.st_size;  // 文件的大小
    long block_size = st.st_blksize;  // 文件最佳块大小
    block_size = power_of_2(block_size);  // 将block-size变为2的整数次幂
    if (file_size <= 128 * 1024) {
        // 小文件，小于等于128KB
        muti = 1;
    }
    else if (file_size <= 1 * 1024 * 1024) {
        // 中文件，小于等于1MB
        muti = 2;
    }
    else if (file_size <= 128 * 1024 * 1024) {
        // 大型文件，小于等于128MB
        muti = 4;
    }
    else {
        // 特大文件
        muti = 16;
    }
    return muti * block_size * 4096;
}


/*分配一段内存，长度不小于`size`并且返回一个对齐到内存页起始的指针`ptr`*/
char* align_alloc(size_t size) {
    char* buf = (char*)malloc(page_size + size - 1);
    if (!buf) {perror("malloc"); exit(1);}
    long buf_addr = (long)buf;
    offset = buf_addr % page_size;
    return buf + (page_size - offset);  // 对齐下一页
}


/*给出一个先前从`align_alloc`返回的指针并释放之前分配的内存*/
void align_free(void* ptr) {
    // 原始地址计算
    void* origin_ptr = ptr + offset - page_size; 
    free(origin_ptr);    
}


int main(int argc, char *argv[]) {
    init_pagesize();
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        exit(1);
    }
    
    int fd = open(argv[1], O_RDONLY);
    if (fd == -1) {
        perror("open");
        exit(1);
    }

    long buf_size = io_blocksize(fd);
    char* buf = align_alloc(buf_size);
    if (buf == NULL) {perror("malloc");exit(1);}

    int read_size;
    while ((read_size = read(fd, buf, buf_size))) {
        if (read_size == -1) {perror("read");exit(1);}
        write(STDOUT_FILENO, buf, read_size);
        if (read_size < buf_size) {
            align_free(buf);
            close(fd);
            exit(0);
        }
    }
    align_free(buf);
    close(fd);
    exit(0);
}
