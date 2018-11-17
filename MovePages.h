#ifndef _MOVE_PAGES_H
#define _MOVE_PAGES_H

#include <unordered_map>
#include <string>
#include <vector>

class Formatter;

#define MPOL_MF_SW_YOUNG (1<<7)

typedef std::unordered_map<int, int> MovePagesStatusCount;

class MovePages
{
  public:
    MovePages();
    ~MovePages() {};

    void set_pid(pid_t i)                     { pid = i; }
    void set_target_node(int nid)             { target_node = nid; }
    void set_page_shift(int t)                { page_shift = t; }
    void set_batch_size(unsigned long npages) { batch_size = npages; }
    void set_flags(int f)                     { flags = f; }

    long move_pages(std::vector<void *>& addrs);

    std::vector<int>& get_status()            { return status; }
    MovePagesStatusCount& get_status_count()  { return status_count; }

  private:
    void calc_status_count();

  private:
    pid_t pid;
    int flags;
    int target_node;

    unsigned long page_shift;
    unsigned long batch_size; // ignored: no need to implement for now

    // Get the status after migration
    std::vector<int> status;
    std::vector<int> nodes;

    MovePagesStatusCount status_count;
};

#endif
// vim:set ts=2 sw=2 et: