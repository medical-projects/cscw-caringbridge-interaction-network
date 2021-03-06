import json
import os
import sys
import csv as csv
import re
from tqdm import tqdm
import multiprocessing as mp

POISON = "POISON" # this is the kill switch for the write process
pwd = "/home/srivbane/shared/caringbridge/data/projects/sna-social-support/csv_data/"

def process_pair(pair_lines, queue, f_uid, t_uid):
    amps = 0; jr = 0; gb = 0;
    first_int_createdAt = sys.maxsize;
    last_int_createdAt = -1
    for line in pair_lines:
        from_userId, siteId, to_userId, c_type, createdAt_str = line.split(",")
        assert f_uid == int(from_userId) and t_uid == int(to_userId), \
        "{} - {}, {} - {}".format(f_uid, from_userId, t_uid, to_userId)
        createdAt = int(createdAt_str)
        if (c_type == "amps"):
            amps += 1
        elif (c_type == "reply"):
            jr += 1
        elif (c_type == "guestbook"):
            gb += 1
        if createdAt < first_int_createdAt:
            first_int_createdAt = createdAt
        if createdAt > last_int_createdAt:
            last_int_createdAt = createdAt
    output_tuple = (f_uid, t_uid, first_int_createdAt, last_int_createdAt, gb, amps, jr)
    queue.put(output_tuple)

class WriterProcess(mp.Process):

    def __init__(self, outfile, queue, **kwargs):
        super(WriterProcess, self).__init__()
        self.outfile = outfile
        self.queue = queue
        self.kwargs = kwargs

    def run(self):
        with open(self.outfile, 'w', encoding="utf-8") as outfile:
            while True:
                result = self.queue.get()
                if result == POISON:
                    break
                try:
                    #uid, ti, fi, li = result
                    #line = "{},{},{},{}\n".format(uid, ti, fi, li)
                    t_uid, f_uid, fi, li, tg, ta, tr = result
                    line = "{},{},{},{},{},{},{}\n".format(t_uid, f_uid, fi, li, tg, ta, tr)
                    outfile.write(line)
                except mp.TimeoutError:
                    sys.stderr.write("Process caused a timeout in mp.")

def process(inpath, outpath, max_res = None, line_lim = None):
    with mp.Pool(processes=24) as pool:
        results = []
        manager = mp.Manager()
        queue = manager.Queue()
        w_process = WriterProcess(outfile=outpath, queue=queue)
        w_process.start()
        print("Processes started.")
        f_uid = -1; t_uid = -1;
        with open(inpath, 'r', encoding='utf-8') as infile:
            uid_lines = []; pair_lines = [];
            for i, line in enumerate(infile):

                """ Both task one and task two are coded in """

                # TASK TWO
                tokens = line.split(",")
                if tokens[0] == "from_userId" or int(tokens[0]) == 0 \
                or tokens[2] == "to_userId" or int(tokens[2]) == 0:
                    continue
                curr_fuid = int(tokens[0])
                curr_tuid = int(tokens[2])
                # if i % 1000 == 1:
                    # print(i, f_uid, t_uid, len(pair_lines))
                if f_uid != curr_fuid or t_uid != curr_tuid:
                    if f_uid != -1 and t_uid != -1:
                        result = pool.apply_async(process_pair, (pair_lines, queue, f_uid, t_uid,))
                        results.append(result)
                    f_uid = curr_fuid
                    t_uid = curr_tuid
                    pair_lines = []
                pair_lines.append(line)

                """ End of modified code for task description """

                if max_res is not None and len(results) == max_res:
                    for result in tqdm(results, desc="Joining Results [Inner nest]"):
                        result.get()
                    results = []
                if line_lim is not None and i > line_lim:
                    break

            """ Change this code for the function being processed """
            result = pool.apply_async(process_pair, (pair_lines, queue, f_uid, t_uid,))
            results.append(result)
            """ End of changed code for the multiprocessing fw"""

        for result in tqdm(results, desc="Joining Results [Outer nest]"):
            result.get()

        queue.put(POISON)
        w_process.join()
        manager.shutdown()
    print("Finished!")

def main():
    inpath = os.path.join(pwd, "ints.csv")
    outpath = os.path.join(pwd, "dynamic_pairs.csv") # change based on task
    process(inpath, outpath, max_res = 1000000, line_lim = None)

if __name__ == "__main__":
    main()

